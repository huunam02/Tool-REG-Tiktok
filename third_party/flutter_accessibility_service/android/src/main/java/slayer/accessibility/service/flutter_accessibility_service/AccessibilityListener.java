package slayer.accessibility.service.flutter_accessibility_service;

import static slayer.accessibility.service.flutter_accessibility_service.Constants.*;
import static slayer.accessibility.service.flutter_accessibility_service.FlutterAccessibilityServicePlugin.CACHED_TAG;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.annotation.TargetApi;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.util.LruCache;
import android.view.Gravity;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import androidx.annotation.RequiresApi;


import com.google.gson.Gson;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.stream.Collectors;

import io.flutter.plugin.common.MethodChannel;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;


public class AccessibilityListener extends AccessibilityService {
    private static AccessibilityListener instance;
    private static WindowManager mWindowManager;
    private static FlutterView mOverlayView;
    static private boolean isOverlayShown = false;
    private static final int CACHE_SIZE = 4 * 1024 * 1024; // 4Mib
    private static final int maxDepth = 20;
    private static LruCache<String, AccessibilityNodeInfo> nodeMap =
            new LruCache<>(CACHE_SIZE);
    private static final int DEFAULT_MAX_TREE_DEPTH = 15;
    private int maximumTreeDepth = DEFAULT_MAX_TREE_DEPTH;

    public static AccessibilityNodeInfo getNodeInfo(String id) {
        return nodeMap.get(id);
    }

    static AccessibilityListener currentInstance() { return instance; }

    @RequiresApi(api = Build.VERSION_CODES.N)
    @Override
    public void onAccessibilityEvent(AccessibilityEvent accessibilityEvent) {
        try {
            final int eventType = accessibilityEvent.getEventType();
            AccessibilityNodeInfo parentNodeInfo = accessibilityEvent.getSource();
            AccessibilityWindowInfo windowInfo = null;
            List<String> nextTexts = new ArrayList<>();
            List<Integer> actions = new ArrayList<>();
            List<HashMap<String, Object>> subNodeActions = new ArrayList<>();
            HashSet<AccessibilityNodeInfo> traversedNodes = new HashSet<>();
            HashMap<String, Object> data = new HashMap<>();
            if (parentNodeInfo == null) {
                return;
            }
            String nodeId = generateNodeId(parentNodeInfo);
            String packageName = parentNodeInfo.getPackageName().toString();
            // Host WebView is read on demand through a redacted snapshot.
            // Never persist its editable fields in the legacy event mailbox.
            if (getPackageName().equals(packageName)) return;
            storeNode(nodeId, parentNodeInfo);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                windowInfo = parentNodeInfo.getWindow();
            }


            Intent intent = new Intent(ACCESSIBILITY_INTENT);

            data.put("mapId", nodeId);
            data.put("packageName", packageName);
            data.put("eventType", eventType);
            data.put("actionType", accessibilityEvent.getAction());
            data.put("eventTime", accessibilityEvent.getEventTime());
            data.put("movementGranularity", accessibilityEvent.getMovementGranularity());
            Rect rect = new Rect();
            parentNodeInfo.getBoundsInScreen(rect);
            data.put("screenBounds", getBoundingPoints(rect));
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                data.put("contentChangeTypes", accessibilityEvent.getContentChangeTypes());
            }
            if (parentNodeInfo.getText() != null) {
                data.put("capturedText", parentNodeInfo.getText().toString());
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                data.put("nodeId", parentNodeInfo.getViewIdResourceName());
            }
            getSubNodes(parentNodeInfo, subNodeActions, traversedNodes, 0);
            data.put("nodesText", nextTexts);
            actions.addAll(parentNodeInfo.getActionList().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList()));
            data.put("parentActions", actions);
            data.put("subNodesActions", subNodeActions);
            data.put("isClickable", parentNodeInfo.isClickable());
            data.put("isScrollable", parentNodeInfo.isScrollable());
            data.put("isFocusable", parentNodeInfo.isFocusable());
            data.put("isCheckable", parentNodeInfo.isCheckable());
            data.put("isLongClickable", parentNodeInfo.isLongClickable());
            data.put("isEditable", parentNodeInfo.isEditable());
            if (windowInfo != null) {
                data.put("isActive", windowInfo.isActive());
                data.put("isFocused", windowInfo.isFocused());
                data.put("windowType", windowInfo.getType());
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    data.put("isPip", windowInfo.isInPictureInPictureMode());
                }
            }
            storeToSharedPrefs(data);
            intent.putExtra(SEND_BROADCAST, true);
            sendBroadcast(intent);
        } catch (Exception ex) {
            Log.e("EVENT", "onAccessibilityEvent: " + ex.getMessage());
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        boolean globalAction = intent.getBooleanExtra(INTENT_GLOBAL_ACTION, false);
        boolean systemActions = intent.getBooleanExtra(INTENT_SYSTEM_GLOBAL_ACTIONS, false);
        if (systemActions && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            List<Integer> actions = getSystemActions().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList());
            Intent broadcastIntent = new Intent(BROD_SYSTEM_GLOBAL_ACTIONS);
            broadcastIntent.putIntegerArrayListExtra("actions", new ArrayList<>(actions));
            sendBroadcast(broadcastIntent);
        }
        if (globalAction) {
            int actionId = intent.getIntExtra(INTENT_GLOBAL_ACTION_ID, 8);
            performGlobalAction(actionId);
        }
        Log.d("CMD_STARTED", "onStartCommand: " + startId);
        return START_STICKY;
    }


    @RequiresApi(api = Build.VERSION_CODES.N)
    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    void getSubNodes(AccessibilityNodeInfo node, List<HashMap<String, Object>> arr, HashSet<AccessibilityNodeInfo> traversedNodes, int currentDepth) {
        if (currentDepth >= maximumTreeDepth || node == null) {
            if (currentDepth >= maximumTreeDepth) {
                Log.d("TREE_DEPTH", "Maximum tree depth reached: " + currentDepth);
            }
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            if (traversedNodes.contains(node)) return;
            traversedNodes.add(node);
            String mapId = generateNodeId(node);
            AccessibilityWindowInfo windowInfo = null;
            HashMap<String, Object> nested = new HashMap<>();
            Rect rect = new Rect();
            node.getBoundsInScreen(rect);
            windowInfo = node.getWindow();
            nested.put("mapId", mapId);
            nested.put("nodeId", node.getViewIdResourceName());
            nested.put("capturedText", node.getText());
            nested.put("screenBounds", getBoundingPoints(rect));
            nested.put("isClickable", node.isClickable());
            nested.put("isScrollable", node.isScrollable());
            nested.put("isFocusable", node.isFocusable());
            nested.put("isCheckable", node.isCheckable());
            nested.put("isLongClickable", node.isLongClickable());
            nested.put("isEditable", node.isEditable());
            nested.put("parentActions", node.getActionList().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList()));
            if (windowInfo != null) {
                nested.put("isActive", node.getWindow().isActive());
                nested.put("isFocused", node.getWindow().isFocused());
                nested.put("windowType", node.getWindow().getType());
            }
            arr.add(nested);
            storeNode(mapId, node);
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child == null)
                    continue;
                getSubNodes(child, arr, traversedNodes, currentDepth + 1);
            }
        }
    }

    private HashMap<String, Integer> getBoundingPoints(Rect rect) {
        HashMap<String, Integer> frame = new HashMap<>();
        frame.put("left", rect.left);
        frame.put("right", rect.right);
        frame.put("top", rect.top);
        frame.put("bottom", rect.bottom);
        frame.put("width", rect.width());
        frame.put("height", rect.height());
        return frame;
    }


    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP_MR1)
    @Override
    protected void onServiceConnected() {
        instance = this;
        mWindowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        initializeOverlayIfReady();
    }

    // Android can bind this service before any Activity/Flutter engine exists.
    // Gestures and events need the service instance, not the optional overlay.
    private static boolean initializeOverlayIfReady() {
        if (mOverlayView != null) return true;
        FlutterEngine engine = FlutterEngineCache.getInstance().get(CACHED_TAG);
        if (instance == null || engine == null) return false;
        mOverlayView = new FlutterView(instance.getApplicationContext(),
            new FlutterTextureView(instance.getApplicationContext()));
        mOverlayView.attachToFlutterEngine(engine);
        mOverlayView.setFitsSystemWindows(true);
        mOverlayView.setFocusable(true);
        mOverlayView.setFocusableInTouchMode(true);
        mOverlayView.setBackgroundColor(Color.TRANSPARENT);
        return true;
    }

    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP_MR1)
    static public void showOverlay(int width, int height, int gravity, boolean clickableThrough) {
        if (!initializeOverlayIfReady()) return;
        if (!isOverlayShown) {
            WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
            lp.type = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY;
            lp.format = PixelFormat.TRANSLUCENT;
            lp.width = width;
            lp.height = height;
            if (!clickableThrough) {
                lp.flags |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
            } else {
                lp.flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
            }
            lp.gravity = gravity;
            mWindowManager.addView(mOverlayView, lp);
            isOverlayShown = true;
        }
    }

    static public void removeOverlay() {
        if (isOverlayShown) {
            mWindowManager.removeView(mOverlayView);
            isOverlayShown = false;
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        removeOverlay();
        if (mOverlayView != null) {
            mOverlayView.detachFromFlutterEngine();
            mOverlayView = null;
        }
        SharedPreferences sharedPreferences = getSharedPreferences(SHARED_PREFS_TAG, MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedPreferences.edit();
        editor.remove(ACCESSIBILITY_NODE).apply();
    }

    @Override
    public void onInterrupt() {
    }

    /**
     * One finger that stays down across [segments] (press-hold, move, hold),
     * each continuing the previous stroke; the finger lifts after the last.
     * Each segment's path starts where the previous one ended.
     */
    @RequiresApi(api = Build.VERSION_CODES.O)
    public static void performContinuousGesture(List<Object> segments, MethodChannel.Result result) {
        if (instance == null || segments == null || segments.isEmpty()) {
            result.success(false);
            return;
        }
        dispatchSegment(instance, segments, 0, null, 0, 0, result);
    }

    @SuppressWarnings("unchecked")
    @RequiresApi(api = Build.VERSION_CODES.O)
    private static void dispatchSegment(AccessibilityListener service, List<Object> segments, int index,
            GestureDescription.StrokeDescription previous, int previousX, int previousY,
            MethodChannel.Result result) {
        try {
            Map<String, Object> segment = (Map<String, Object>) segments.get(index);
            List<Object> pointObjs = (List<Object>) segment.get("path");
            int duration = ((Number) segment.get("duration")).intValue();
            Path path = new Path();
            Map<String, Object> first = (Map<String, Object>) pointObjs.get(0);
            // Android injects integer screen pixels. A subpixel segment can
            // become stationary after rounding and produce no MotionEvents;
            // Android 9 rejects that continuation instead of holding still.
            final int startX = Math.round(((Number) first.get("x")).floatValue());
            final int startY = Math.round(((Number) first.get("y")).floatValue());
            int lastX = startX, lastY = startY;
            boolean stationary = true;
            path.moveTo(startX, startY);
            for (int i = 1; i < pointObjs.size(); i++) {
                Map<String, Object> pt = (Map<String, Object>) pointObjs.get(i);
                lastX = Math.round(((Number) pt.get("x")).floatValue());
                lastY = Math.round(((Number) pt.get("y")).floatValue());
                stationary &= lastX == startX && lastY == startY;
                path.lineTo(lastX, lastY);
            }
            final int endX = lastX, endY = lastY;
            boolean more = index + 1 < segments.size();
            if (previous != null && (startX != previousX || startY != previousY)) {
                Log.w("GESTURE", "continuous gesture has disconnected paths at segment " + index);
                result.success(false);
                return;
            }
            if (previous != null && stationary && more) {
                // Keep the existing pointer down without sending an empty
                // continuation. Retain its stroke id for the next movement.
                new Handler(Looper.getMainLooper()).postDelayed(() ->
                    dispatchSegment(service, segments, index + 1, previous, endX, endY, result), duration);
                return;
            }
            GestureDescription.StrokeDescription stroke = previous == null
                ? new GestureDescription.StrokeDescription(path, 0, duration, more)
                : previous.continueStroke(path, 0, duration, more);
            final long startedAt = SystemClock.uptimeMillis();
            boolean sent = service.dispatchGesture(new GestureDescription.Builder().addStroke(stroke).build(),
                new AccessibilityService.GestureResultCallback() {
                    @Override
                    public void onCompleted(GestureDescription gestureDescription) {
                        if (more) {
                            // A press-only segment can complete at ACTION_DOWN,
                            // before its duration expires. Preserve its hold.
                            long remaining = Math.max(0, startedAt + duration - SystemClock.uptimeMillis());
                            new Handler(Looper.getMainLooper()).postDelayed(() ->
                                dispatchSegment(service, segments, index + 1, stroke, endX, endY, result), remaining);
                        } else new Handler(Looper.getMainLooper()).post(() -> result.success(true));
                    }

                    @Override
                    public void onCancelled(GestureDescription gestureDescription) {
                        Log.w("GESTURE", "continuous gesture cancelled at segment " + index + "/" + segments.size());
                        new Handler(Looper.getMainLooper()).post(() -> result.success(false));
                    }
                }, null);
            if (!sent) {
                Log.w("GESTURE", "continuous gesture not sent at segment " + index + "/" + segments.size());
                result.success(false);
            }
        } catch (Exception e) {
            Log.e("GESTURE", "performContinuousGesture: " + e.getMessage());
            result.success(false);
        }
    }

    @SuppressWarnings("unchecked")
    @RequiresApi(api = Build.VERSION_CODES.N)
    public static void performDispatchGesture(List<Object> strokes, MethodChannel.Result result) {
        if (instance == null) {
            result.success(false);
            return;
        }
        try {
            GestureDescription.Builder gestureBuilder = new GestureDescription.Builder();
            for (Object strokeObj : strokes) {
                Map<String, Object> stroke = (Map<String, Object>) strokeObj;
                List<Object> pointObjs = (List<Object>) stroke.get("path");
                int startTime = ((Number) stroke.get("startTime")).intValue();
                int duration = ((Number) stroke.get("duration")).intValue();

                Path path = new Path();
                if (pointObjs != null && !pointObjs.isEmpty()) {
                    Map<String, Object> first = (Map<String, Object>) pointObjs.get(0);
                    path.moveTo(((Number) first.get("x")).floatValue(), ((Number) first.get("y")).floatValue());
                    for (int i = 1; i < pointObjs.size(); i++) {
                        Map<String, Object> pt = (Map<String, Object>) pointObjs.get(i);
                        path.lineTo(((Number) pt.get("x")).floatValue(), ((Number) pt.get("y")).floatValue());
                    }
                }
                gestureBuilder.addStroke(new GestureDescription.StrokeDescription(path, startTime, duration));
            }

            instance.dispatchGesture(gestureBuilder.build(), new AccessibilityService.GestureResultCallback() {
                @Override
                public void onCompleted(GestureDescription gestureDescription) {
                    new Handler(Looper.getMainLooper()).post(() -> result.success(true));
                }

                @Override
                public void onCancelled(GestureDescription gestureDescription) {
                    new Handler(Looper.getMainLooper()).post(() -> result.success(false));
                }
            }, null);
        } catch (Exception e) {
            Log.e("GESTURE", "performDispatchGesture: " + e.getMessage());
            result.success(false);
        }
    }


    private String generateNodeId(AccessibilityNodeInfo node) {
        return node.getWindowId() + "_" + node.hashCode();
    }

    private void storeNode(String uuid, AccessibilityNodeInfo node) {
        if (node == null) {
            return;
        }
        nodeMap.put(uuid, node);
    }

    void storeToSharedPrefs(HashMap<String, Object> data) {
        SharedPreferences sharedPreferences = getSharedPreferences(SHARED_PREFS_TAG, MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedPreferences.edit();
        Gson gson = new Gson();
        String json = gson.toJson(data);
        editor.putString(ACCESSIBILITY_NODE, json);
        editor.apply();
    }

}
