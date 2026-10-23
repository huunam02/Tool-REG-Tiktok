package com.brisklane.browser.proxy;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.junit.After;
import org.junit.Test;
import static org.junit.Assert.*;

/** Real loopback sockets and synthetic credentials; no external service calls. */
public class HttpConnectSocksBridgeTest {
    private final List<AutoCloseable> resources = new ArrayList<>();

    @After public void cleanup() throws Exception {
        for (int i = resources.size() - 1; i >= 0; i--) resources.get(i).close();
    }

    private ServerSocket proxy() throws Exception {
        ServerSocket server = new ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"));
        server.setSoTimeout(5000);
        resources.add(server);
        return server;
    }

    private HttpConnectSocksBridge bridge(ServerSocket server) throws Exception {
        HttpConnectSocksBridge bridge = new HttpConnectSocksBridge("127.0.0.1", "localhost",
            server.getLocalPort(), false, "fixture-user", "fixture-pass");
        resources.add(bridge);
        return bridge;
    }

    private Socket client(HttpConnectSocksBridge bridge, String password) throws Exception {
        Socket socket = new Socket("127.0.0.1", bridge.getPort());
        resources.add(socket);
        socket.setSoTimeout(5000);
        OutputStream output = socket.getOutputStream();
        InputStream input = socket.getInputStream();
        output.write(new byte[] {5, 1, 2});
        assertArrayEquals(new byte[] {5, 2}, read(input, 2));
        byte[] user = bridge.getUsername().getBytes(StandardCharsets.UTF_8);
        byte[] pass = password.getBytes(StandardCharsets.UTF_8);
        output.write(1);
        output.write(user.length);
        output.write(user);
        output.write(pass.length);
        output.write(pass);
        output.flush();
        byte[] authentication = read(input, 2);
        assertEquals(1, authentication[0]);
        assertEquals(password.equals(bridge.getPassword()) ? 0 : 1, authentication[1]);
        return socket;
    }

    private void request(Socket socket, int command, byte[] address, int type, int port) throws Exception {
        OutputStream output = socket.getOutputStream();
        output.write(new byte[] {5, (byte) command, 0, (byte) type});
        if (type == 3) output.write(address.length);
        output.write(address);
        output.write(new byte[] {(byte) (port >> 8), (byte) port});
        output.flush();
    }

    private String header(InputStream input) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int end = 0;
        while (bytes.size() < 16384) {
            int b = input.read();
            if (b < 0) throw new AssertionError("Missing HTTP headers");
            bytes.write(b);
            end = (end << 8) | b;
            if (end == 0x0d0a0d0a) return bytes.toString("US-ASCII");
        }
        throw new AssertionError("Oversized HTTP headers");
    }

    private static byte[] read(InputStream input, int count) throws Exception {
        byte[] bytes = new byte[count];
        int offset = 0;
        while (offset < count) {
            int n = input.read(bytes, offset, count - offset);
            if (n < 0) throw new AssertionError("Unexpected socket EOF");
            offset += n;
        }
        return bytes;
    }

    @Test public void authenticatesHttpConnectAndRelaysBothDirectionsWithoutLosingEarlyBytes() throws Exception {
        ServerSocket server = proxy();
        HttpConnectSocksBridge bridge = bridge(server);
        CompletableFuture<String> received = CompletableFuture.supplyAsync(() -> {
            try (Socket upstream = server.accept()) {
                upstream.setSoTimeout(5000);
                String request = header(upstream.getInputStream());
                // Header and first tunnel bytes arrive in the same write.
                upstream.getOutputStream().write("HTTP/1.1 200 Connection established\r\n\r\nHELLO".getBytes(StandardCharsets.US_ASCII));
                byte[] payload = read(upstream.getInputStream(), 4096);
                assertEquals(-1, upstream.getInputStream().read()); // Client half-close.
                upstream.getOutputStream().write(payload);
                return request;
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        Socket client = client(bridge, bridge.getPassword());
        request(client, 1, "example.test".getBytes(StandardCharsets.US_ASCII), 3, 443);
        assertEquals(0, read(client.getInputStream(), 10)[1]);
        assertArrayEquals("HELLO".getBytes(StandardCharsets.US_ASCII), read(client.getInputStream(), 5));
        byte[] payload = new byte[4096];
        for (int i = 0; i < payload.length; i++) payload[i] = (byte) i;
        client.getOutputStream().write(payload);
        client.shutdownOutput();
        assertArrayEquals(payload, read(client.getInputStream(), payload.length));
        String request = received.get(5, TimeUnit.SECONDS);
        assertTrue(request.startsWith("CONNECT example.test:443 HTTP/1.1\r\n"));
        assertTrue(request.contains("Host: example.test:443\r\n"));
        assertTrue(request.contains("Proxy-Authorization: Basic " + Base64.getEncoder()
            .encodeToString("fixture-user:fixture-pass".getBytes(StandardCharsets.UTF_8)) + "\r\n"));
    }

    @Test public void httpAuthenticationRejectionIsNotReportedAsSuccessfulTunnel() throws Exception {
        ServerSocket server = proxy();
        HttpConnectSocksBridge bridge = bridge(server);
        CompletableFuture<Void> upstream = CompletableFuture.runAsync(() -> {
            try (Socket socket = server.accept()) {
                header(socket.getInputStream());
                socket.getOutputStream().write("HTTP/1.0 407 Proxy Authentication Required\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        Socket client = client(bridge, bridge.getPassword());
        request(client, 1, new byte[] {1, 2, 3, 4}, 1, 443);
        assertEquals(2, read(client.getInputStream(), 10)[1]);
        upstream.get(5, TimeUnit.SECONDS);
    }

    @Test public void requiresPrivateLoopbackCredentialsAndRejectsUdp() throws Exception {
        ServerSocket server = proxy();
        HttpConnectSocksBridge bridge = bridge(server);
        Socket unauthorized = client(bridge, "wrong-password");
        assertEquals(-1, unauthorized.getInputStream().read());
        Socket udp = client(bridge, bridge.getPassword());
        request(udp, 3, new byte[] {1, 2, 3, 4}, 1, 53);
        assertEquals(7, read(udp.getInputStream(), 10)[1]);
    }

    @Test public void profileShutdownClosesPendingClientsAndListener() throws Exception {
        ServerSocket server = proxy();
        HttpConnectSocksBridge bridge = bridge(server);
        Socket client = client(bridge, bridge.getPassword());
        bridge.close();
        assertEquals(-1, client.getInputStream().read());
        assertThrows(java.net.ConnectException.class, () -> new Socket("127.0.0.1", bridge.getPort()));
    }

    @Test public void httpsProxyDoesNotDowngradeToPlaintextWhenTlsFails() throws Exception {
        ServerSocket server = proxy();
        HttpConnectSocksBridge bridge = new HttpConnectSocksBridge("127.0.0.1", "localhost",
            server.getLocalPort(), true, "fixture-user", "fixture-pass");
        resources.add(bridge);
        CompletableFuture<Integer> firstByte = CompletableFuture.supplyAsync(() -> {
            try (Socket upstream = server.accept()) {
                upstream.setSoTimeout(5000);
                int first = upstream.getInputStream().read();
                upstream.getOutputStream().write("HTTP/1.1 400 Bad Request\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
                return first;
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        Socket client = client(bridge, bridge.getPassword());
        request(client, 1, new byte[] {1, 2, 3, 4}, 1, 443);
        assertNotEquals(0, read(client.getInputStream(), 10)[1]);
        assertEquals(0x16, (int) firstByte.get(5, TimeUnit.SECONDS)); // TLS handshake, not CONNECT/authentication.
    }
}
