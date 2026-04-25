package com.dreamwork.app;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final String EMULATOR_CORE_API_URL = "http://10.0.2.2:8080";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final CoreApiClient client = new CoreApiClient(EMULATOR_CORE_API_URL);

    private TextView statusView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
        checkHealth();
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }

    private ScrollView createContentView() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER_HORIZONTAL);
        int padding = (int) (24 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, padding, padding, padding);

        TextView titleView = new TextView(this);
        titleView.setText("DreamWork Android Demo");
        titleView.setTextSize(24);
        layout.addView(titleView);

        statusView = new TextView(this);
        statusView.setText("Starting...");
        statusView.setTextSize(16);
        statusView.setPadding(0, padding, 0, padding);
        layout.addView(statusView);

        Button healthButton = new Button(this);
        healthButton.setText("Check Core API");
        healthButton.setOnClickListener(view -> checkHealth());
        layout.addView(healthButton);

        Button seedButton = new Button(this);
        seedButton.setText("Seed Person");
        seedButton.setOnClickListener(view -> seedPerson());
        layout.addView(seedButton);

        Button readButton = new Button(this);
        readButton.setText("Read Person");
        readButton.setOnClickListener(view -> readPerson());
        layout.addView(readButton);

        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(layout);
        return scrollView;
    }

    private void checkHealth() {
        runBackendCall("Checking " + EMULATOR_CORE_API_URL + "/healthz", client::health);
    }

    private void seedPerson() {
        runBackendCall("Seeding demo person...", client::seedDemoPerson);
    }

    private void readPerson() {
        runBackendCall("Reading demo person...", client::readDemoPerson);
    }

    private void runBackendCall(String pendingMessage, BackendCall call) {
        setStatus(pendingMessage);
        executor.execute(() -> {
            try {
                String response = call.run();
                setStatus("Success:\n" + response);
            } catch (Exception error) {
                setStatus("Error:\n" + error.getMessage());
            }
        });
    }

    private void setStatus(String message) {
        mainHandler.post(() -> statusView.setText(message));
    }

    private interface BackendCall {
        String run() throws Exception;
    }
}
