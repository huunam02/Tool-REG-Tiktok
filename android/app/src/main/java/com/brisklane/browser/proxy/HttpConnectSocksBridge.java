package com.brisklane.browser.proxy;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Semaphore;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/** App-private SOCKS5 TCP endpoint backed by one HTTP CONNECT per connection. */
public final class HttpConnectSocksBridge implements Closeable {
    private static final int HANDSHAKE_TIMEOUT = 15000;
    private final String upstreamAddress, upstreamHost, username, password;
    private final int upstreamPort;
    private final boolean tls;
    private final ServerSocket listener;
    private final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
    private final Semaphore connections = new Semaphore(64);
    private final ThreadPoolExecutor workers = new ThreadPoolExecutor(0, 128, 30,
        TimeUnit.SECONDS, new SynchronousQueue<>(), task -> {
            Thread thread = new Thread(task, "http-proxy-relay");
            thread.setDaemon(true);
            return thread;
        });
    private final String localUsername = UUID.randomUUID().toString();
    private final String localPassword = UUID.randomUUID().toString();
    private volatile boolean closed;

    public HttpConnectSocksBridge(String upstreamAddress, String upstreamHost, int upstreamPort,
            boolean tls, String username, String password) throws IOException {
        this.upstreamAddress = upstreamAddress;
        this.upstreamHost = upstreamHost;
        this.upstreamPort = upstreamPort;
        this.tls = tls;
        this.username = username;
        this.password = password;
        listener = new ServerSocket();
        listener.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0));
        Thread acceptor = new Thread(this::accept, "http-proxy-listener");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    public int getPort() { return listener.getLocalPort(); }
    public String getUsername() { return localUsername; }
    public String getPassword() { return localPassword; }

    private void accept() {
        while (!closed) {
            Socket client = null;
            boolean acquired = false;
            try {
                client = listener.accept();
                if (closed || !(acquired = connections.tryAcquire())) {
                    client.close();
                    continue;
                }
                sockets.add(client);
                final Socket connection = client;
                workers.execute(() -> handle(connection));
            } catch (IOException | java.util.concurrent.RejectedExecutionException error) {
                if (client != null) {
                    sockets.remove(client);
                    closeQuietly(client);
                }
                if (acquired) connections.release();
                if (!closed && listener.isClosed()) return;
            }
        }
    }

    private void handle(Socket client) {
        Socket upstream = null;
        boolean replied = false;
        try {
            client.setSoTimeout(HANDSHAKE_TIMEOUT);
            InputStream input = client.getInputStream();
            OutputStream output = client.getOutputStream();
            if (!authenticate(input, output)) return;
            if (read(input) != 5) throw new IOException("Invalid SOCKS version");
            int command = read(input), reserved = read(input), type = read(input);
            if (command != 1 || reserved != 0) {
                reply(output, 7);
                return;
            }
            String host;
            if (type == 1 || type == 4) {
                byte[] address = bytes(input, type == 1 ? 4 : 16);
                host = InetAddress.getByAddress(address).getHostAddress();
                if (type == 4) host = "[" + host + "]";
            } else if (type == 3) {
                host = new String(bytes(input, read(input)), StandardCharsets.US_ASCII);
                if (!host.matches("[A-Za-z0-9._-]+")) throw new IOException("Invalid hostname");
            } else {
                reply(output, 8);
                return;
            }
            int port = (read(input) << 8) | read(input);
            if (port == 0) throw new IOException("Invalid target port");
            upstream = connect();
            String authority = host + ":" + port;
            String authorization = username.isEmpty() ? "" : "Proxy-Authorization: Basic " +
                Base64.getEncoder().encodeToString((username + ":" + password)
                    .getBytes(StandardCharsets.UTF_8)) + "\r\n";
            upstream.getOutputStream().write(("CONNECT " + authority + " HTTP/1.1\r\nHost: " +
                authority + "\r\n" + authorization + "\r\n").getBytes(StandardCharsets.US_ASCII));
            upstream.getOutputStream().flush();
            int status = responseStatus(upstream.getInputStream());
            if (status < 200 || status >= 300) {
                reply(output, status == 407 ? 2 : 1);
                replied = true;
                return;
            }
            reply(output, 0);
            replied = true;
            client.setSoTimeout(600000);
            upstream.setSoTimeout(600000);
            relay(client, upstream);
        } catch (IOException | InterruptedException | java.util.concurrent.RejectedExecutionException error) {
            if (error instanceof InterruptedException) Thread.currentThread().interrupt();
            if (!replied) {
                try { reply(client.getOutputStream(), 1); } catch (IOException ignored) { }
            }
        } finally {
            sockets.remove(client);
            closeQuietly(client);
            if (upstream != null) {
                sockets.remove(upstream);
                closeQuietly(upstream);
            }
            connections.release();
        }
    }

    private boolean authenticate(InputStream input, OutputStream output) throws IOException {
        if (read(input) != 5) return false;
        byte[] methods = bytes(input, read(input));
        boolean passwordSupported = false;
        for (byte method : methods) passwordSupported |= method == 2;
        output.write(new byte[] {5, (byte) (passwordSupported ? 2 : 255)});
        output.flush();
        if (!passwordSupported || read(input) != 1) return false;
        byte[] user = bytes(input, read(input));
        byte[] pass = bytes(input, read(input));
        boolean valid = MessageDigest.isEqual(user, localUsername.getBytes(StandardCharsets.UTF_8)) &
            MessageDigest.isEqual(pass, localPassword.getBytes(StandardCharsets.UTF_8));
        output.write(new byte[] {1, (byte) (valid ? 0 : 1)});
        output.flush();
        return valid;
    }

    private Socket connect() throws IOException {
        Socket plain = new Socket();
        Socket connection = plain;
        sockets.add(plain);
        try {
            if (closed) throw new IOException("Bridge closed");
            plain.connect(new InetSocketAddress(upstreamAddress, upstreamPort), HANDSHAKE_TIMEOUT);
            plain.setSoTimeout(HANDSHAKE_TIMEOUT);
            if (!tls) return plain;
            SSLSocket secure = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault())
                .createSocket(plain, upstreamHost, upstreamPort, true);
            connection = secure;
            sockets.add(secure);
            SSLParameters parameters = secure.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            secure.setSSLParameters(parameters);
            secure.setSoTimeout(HANDSHAKE_TIMEOUT);
            secure.startHandshake();
            sockets.remove(plain);
            return secure;
        } catch (IOException error) {
            sockets.remove(connection);
            closeQuietly(connection);
            sockets.remove(plain);
            closeQuietly(plain);
            throw error;
        }
    }

    private void relay(Socket client, Socket upstream) throws IOException, InterruptedException {
        CountDownLatch downstreamFinished = new CountDownLatch(1);
        workers.execute(() -> {
            try { copy(upstream, client); }
            catch (IOException error) { closeQuietly(client); closeQuietly(upstream); }
            finally { downstreamFinished.countDown(); }
        });
        copy(client, upstream);
        downstreamFinished.await();
    }

    private static void copy(Socket from, Socket to) throws IOException {
        byte[] buffer = new byte[16384];
        int count;
        InputStream input = from.getInputStream();
        OutputStream output = to.getOutputStream();
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        output.flush();
        to.shutdownOutput();
    }

    private static int responseStatus(InputStream input) throws IOException {
        // Read exactly the header; a proxy may send tunnel bytes in the same
        // packet. Buffered character readers would consume and lose them.
        ByteArrayOutputStream header = new ByteArrayOutputStream();
        int end = 0;
        while (header.size() < 16384) {
            int value = read(input);
            header.write(value);
            end = (end << 8) | value;
            if (end == 0x0d0a0d0a) {
                String first = new String(header.toByteArray(), StandardCharsets.US_ASCII).split("\r\n", 2)[0];
                if (!first.matches("HTTP/1\\.[01] [0-9]{3}(?: .*)?")) break;
                return Integer.parseInt(first.substring(9, 12));
            }
        }
        throw new IOException("Invalid HTTP CONNECT response");
    }

    private static void reply(OutputStream output, int status) throws IOException {
        output.write(new byte[] {5, (byte) status, 0, 1, 0, 0, 0, 0, 0, 0});
        output.flush();
    }

    private static int read(InputStream input) throws IOException {
        int value = input.read();
        if (value == -1) throw new EOFException();
        return value;
    }

    private static byte[] bytes(InputStream input, int length) throws IOException {
        byte[] value = new byte[length];
        int position = 0;
        while (position < length) {
            int count = input.read(value, position, length - position);
            if (count == -1) throw new EOFException();
            position += count;
        }
        return value;
    }

    private static void closeQuietly(Closeable value) {
        try { value.close(); } catch (IOException ignored) { }
    }

    @Override public void close() {
        closed = true;
        closeQuietly(listener);
        for (Socket socket : sockets) closeQuietly(socket);
        workers.shutdownNow();
    }
}
