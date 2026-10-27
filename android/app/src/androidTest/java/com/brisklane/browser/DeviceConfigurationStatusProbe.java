package com.brisklane.browser;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Temporary, read-only device probe. Outputs status fields only. */
@RunWith(AndroidJUnit4.class)
public class DeviceConfigurationStatusProbe {
    @Test public void writesOnlyConfigurationStatusesAndFailureReasons() throws Exception {
        var context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        JSONArray rows = new JSONArray();
        JSONArray columns = new JSONArray();
        int version;
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(
                context.getDatabasePath("proxies.db").getAbsolutePath(), null,
                SQLiteDatabase.OPEN_READONLY);
             Cursor schema = db.rawQuery("PRAGMA table_info(configurations)", null);
             Cursor cursor = db.rawQuery("SELECT id,statusAccount,signup_failed,has_been_used,registered_at " +
                     "FROM configurations WHERE listed=1 ORDER BY id", null)) {
            version = db.getVersion();
            while (schema.moveToNext()) columns.put(schema.getString(1));
            try (Cursor gpu = db.rawQuery("SELECT count(*) FROM configurations WHERE gpu_profile != ''", null)) {
                gpu.moveToFirst();
                columns.put("gpu_profile_non_empty=" + gpu.getInt(0));
            }
            while (cursor.moveToNext()) {
                JSONObject row = new JSONObject();
                int id = cursor.getInt(0);
                row.put("id", id);
                row.put("status", cursor.getString(1));
                row.put("failed", cursor.getInt(2) == 1);
                row.put("used", cursor.getInt(3) == 1);
                row.put("registeredAt", cursor.isNull(4) ? 0 : cursor.getLong(4));
                JSONArray errors = new JSONArray();
                try (Cursor failures = db.rawQuery(
                        "SELECT message,step,created_at FROM signup_failures " +
                        "WHERE configuration_id=? ORDER BY created_at", new String[]{String.valueOf(id)})) {
                    while (failures.moveToNext()) {
                        JSONObject error = new JSONObject();
                        error.put("message", failures.getString(0).replaceAll(
                            "[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+", "[email]"));
                        error.put("step", failures.getString(1));
                        error.put("at", failures.getLong(2));
                        errors.put(error);
                    }
                }
                row.put("errors", errors);
                rows.put(row);
            }
        }
        Files.write(new File(context.getCodeCacheDir(), "configuration-test-status.json").toPath(),
            new JSONObject().put("version", version).put("columns", columns)
                .put("configurations", rows).toString().getBytes(StandardCharsets.UTF_8));
        assertEquals("Every imported configuration remains stored", 14, rows.length());
    }
}
