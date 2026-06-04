package com.registry.telephony.ami;

import com.registry.telephony.config.TelephonyProperties;
import com.registry.telephony.handlers.HangupLeadIngestService;
import jakarta.annotation.PreDestroy;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "telephony.ami", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class AmiManagerClient {

    private final TelephonyProperties telephonyProperties;
    private final HangupLeadIngestService hangupLeadIngestService;

    private final AtomicBoolean running = new AtomicBoolean(true);
    private volatile Thread worker;
    private volatile Socket currentSocket;

    @EventListener(ApplicationReadyEvent.class)
    public void start() {
        Thread t = new Thread(this::runForever, "telephony-ami-client");
        t.setDaemon(true);
        t.start();
        this.worker = t;
    }

    @PreDestroy
    public void shutdown() {
        running.set(false);
        closeQuietly(currentSocket);
        if (worker != null) {
            worker.interrupt();
        }
    }

    private void runForever() {
        long backoffMs = telephonyProperties.getAmi().getReconnectInitialMs();
        while (running.get()) {
            try {
                runOneSession();
                backoffMs = telephonyProperties.getAmi().getReconnectInitialMs();
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                break;
            } catch (Exception e) {
                if (!running.get()) {
                    break;
                }
                log.warn("AMI session ended ({}); reconnect in {} ms", e.getMessage(), backoffMs);
                try {
                    Thread.sleep(backoffMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
                backoffMs = Math.min(backoffMs * 2, telephonyProperties.getAmi().getReconnectMaxMs());
            }
        }
    }

    private void runOneSession() throws Exception {
        TelephonyProperties.Ami ami = telephonyProperties.getAmi();
        String host = ami.getHost();
        int port = ami.getPort();
        log.info("Connecting AMI {}:{}", host, port);
        Socket socket = new Socket();
        currentSocket = socket;
        socket.connect(new InetSocketAddress(host, port), 15_000);
        socket.setSoTimeout(ami.getReadTimeoutMs());
        try {
            BufferedReader in =
                    new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            BufferedOutputStream out = new BufferedOutputStream(socket.getOutputStream());

            skipWelcome(in);

            writeAction(
                    out,
                    Map.of("Action", "Login", "Username", ami.getUsername(), "Secret", ami.getSecret()));
            Map<String, String> loginResp = readUntilResponseKey(in);
            if (!isSuccess(loginResp)) {
                throw new IllegalStateException(
                        "AMI login failed: " + loginResp.getOrDefault("Message", loginResp.toString()));
            }
            log.info("AMI login accepted");

            writeAction(out, Map.of("Action", "Events", "EventMask", ami.getEventMask()));

            while (running.get()) {
                Map<String, String> msg;
                try {
                    msg = AmiMessageCodec.readMessage(in);
                } catch (SocketTimeoutException ste) {
                    writeAction(out, Map.of("Action", "Ping"));
                    continue;
                }
                if (msg.isEmpty()) {
                    throw new SocketException("AMI peer closed (empty read)");
                }
                if (msg.containsKey("Response")) {
                    continue;
                }
                try {
                    hangupLeadIngestService.onCallEvent(msg);
                } catch (Exception ex) {
                    log.error("AMI handler failed for event {}", msg.get("Event"), ex);
                }
            }
        } finally {
            closeQuietly(socket);
            currentSocket = null;
        }
    }

    private static void skipWelcome(BufferedReader in) throws java.io.IOException {
        String banner = in.readLine();
        if (banner == null || !banner.startsWith("Asterisk Call Manager/")) {
            throw new java.io.IOException("Invalid AMI banner: " + banner);
        }
    }

    private static Map<String, String> readUntilResponseKey(BufferedReader in) throws java.io.IOException {
        while (true) {
            Map<String, String> m = AmiMessageCodec.readMessage(in);
            if (m.containsKey("Response")) {
                return m;
            }
            if (m.isEmpty()) {
                throw new SocketException("AMI closed before login response");
            }
        }
    }

    private static boolean isSuccess(Map<String, String> m) {
        return "Success".equalsIgnoreCase(StringUtils.trimToEmpty(m.get("Response")));
    }

    private static void writeAction(OutputStream out, Map<String, String> fields) throws java.io.IOException {
        out.write(AmiMessageCodec.buildAction(fields));
        out.flush();
    }

    private static void closeQuietly(Socket s) {
        if (s == null) {
            return;
        }
        try {
            s.close();
        } catch (Exception ignored) {
        }
    }
}

