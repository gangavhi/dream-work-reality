package com.dreamwork.app;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

final class CoreApiClient {
    private final String baseUrl;

    CoreApiClient(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    String health() throws IOException {
        return request("GET", "/healthz", null);
    }

    String seedDemoPerson() throws IOException {
        String body = "{\"id\":\"person-42\",\"display_name\":\"Alex Carter\"}";
        return request("POST", "/manual-entry", body);
    }

    String readDemoPerson() throws IOException {
        return request("GET", "/manual-entry/person-42", null);
    }

    private String request(String method, String path, String body) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(baseUrl + path).openConnection();
        connection.setRequestMethod(method);
        connection.setConnectTimeout(5000);
        connection.setReadTimeout(5000);
        connection.setRequestProperty("Accept", "application/json");

        if (body != null) {
            byte[] payload = body.getBytes(StandardCharsets.UTF_8);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("Content-Length", Integer.toString(payload.length));
            try (OutputStream output = connection.getOutputStream()) {
                output.write(payload);
            }
        }

        int statusCode = connection.getResponseCode();
        InputStream stream = statusCode >= 400 ? connection.getErrorStream() : connection.getInputStream();
        String responseBody = readBody(stream);
        if (statusCode >= 400) {
            throw new IOException("HTTP " + statusCode + ": " + responseBody);
        }
        return responseBody;
    }

    private static String readBody(InputStream stream) throws IOException {
        if (stream == null) {
            return "";
        }

        StringBuilder body = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                body.append(line);
            }
        }
        return body.toString();
    }
}
