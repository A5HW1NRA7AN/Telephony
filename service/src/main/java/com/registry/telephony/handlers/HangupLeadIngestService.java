package com.registry.telephony.handlers;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.registry.telephony.config.TelephonyProperties;
import com.registry.telephony.job.LeadDispatchService;
import com.registry.telephony.persistence.CallLeadIngestLog;
import com.registry.telephony.persistence.CallLeadIngestLogRepository;
import com.registry.telephony.persistence.CallLeadProcessingStatus;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Slf4j
public class HangupLeadIngestService {

    private static final String EVENT_HANGUP = "Hangup";
    private static final String LEAD_SOURCE = "Asterisk-MissedCall-Campaign";

    private final TelephonyProperties telephonyProperties;
    private final CallLeadIngestLogRepository repository;
    private final ObjectMapper objectMapper;
    private final LeadDispatchService leadDispatchService;

    @Transactional
    public void onAmiMessage(Map<String, String> message) {
        if (!EVENT_HANGUP.equalsIgnoreCase(message.getOrDefault("Event", ""))) {
            return;
        }
        String context = StringUtils.trimToEmpty(message.get("Context"));
        if (!contextAllowed(context)) {
            return;
        }

        String uniqueid = StringUtils.trimToEmpty(message.get("Uniqueid"));
        if (uniqueid.isEmpty()) {
            log.warn("Hangup without Uniqueid; context={}", context);
            return;
        }

        String linkedid = StringUtils.trimToNull(message.get("Linkedid"));
        String idempotencyKey = idempotencyKey(uniqueid, linkedid);
        if (repository.existsByIdempotencyKey(idempotencyKey)) {
            return;
        }

        JsonNode raw = objectMapper.valueToTree(message);
        ObjectNode lead = buildLeadPayload(message, idempotencyKey);

        CallLeadIngestLog row = new CallLeadIngestLog();
        row.setAsteriskUniqueId(uniqueid);
        row.setAsteriskLinkedId(linkedid);
        row.setIdempotencyKey(idempotencyKey);
        row.setProcessingStatus(CallLeadProcessingStatus.RECEIVED);
        row.setRawAmiSnapshot(raw);
        row.setNormalizedLeadPayload(lead);
        row.setCreatedAt(Instant.now());
        row.setUpdatedAt(Instant.now());

        try {
            repository.saveAndFlush(row);
        } catch (DataIntegrityViolationException ex) {
            return;
        }

        // async job
        leadDispatchService.dispatchAsync(row.getId());
    }

    public static String idempotencyKey(String uniqueid, String linkedid) {
        if (linkedid != null && !linkedid.isBlank()) {
            return linkedid.trim();
        }
        return uniqueid.trim();
    }

    private boolean contextAllowed(String context) {
        for (String allowed : telephonyProperties.getLeadContextAllowlist()) {
            if (allowed != null && context.equals(allowed.trim())) {
                return true;
            }
        }
        return false;
    }

    private ObjectNode buildLeadPayload(Map<String, String> ami, String idempotencyKey) {
        String caller = firstNonBlank(ami.get("CallerIDNum"), ami.get("ConnectedLineNum"));
        String called = firstNonBlank(ami.get("Exten"), ami.get("DNID"), ami.get("ConnectedLineNum"));
        int duration = parseIntSafe(ami.get("BillableSeconds"), 0);
        if (duration == 0) {
            duration = parseIntSafe(ami.get("Duration"), 0);
        }

        Instant startApprox = Instant.now().truncatedTo(ChronoUnit.SECONDS);

        ObjectNode n = objectMapper.createObjectNode();
        n.put("leadId", idempotencyKey);
        
        // Fields required by the registry endpoint
        n.put("phone_number", caller == null ? "" : caller);
        n.put("location", "Unknown"); // Default location since PSTN doesn't provide it
        
        // Original fields
        n.put("callerNumber", caller == null ? "" : caller);
        n.put("calledNumber", called == null ? "" : called);
        n.put("callStartTime", startApprox.toString());
        n.put("callDurationSeconds", duration);
        n.put("callStatus", "MISSED");
        n.put("leadSource", LEAD_SOURCE);
        return n;
    }

    private static String firstNonBlank(String... values) {
        if (values == null) {
            return null;
        }
        for (String v : values) {
            if (v != null && !v.isBlank()) {
                return v.trim();
            }
        }
        return null;
    }

    private static int parseIntSafe(String raw, int defaultVal) {
        if (raw == null || raw.isBlank()) {
            return defaultVal;
        }
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            return defaultVal;
        }
    }
}

