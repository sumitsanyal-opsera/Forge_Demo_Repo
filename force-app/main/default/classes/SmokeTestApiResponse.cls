/**
 * Fluent builder for all REST API responses in the Smoke Test system.
 *
 * Usage examples:
 *   SmokeTestApiResponse.error400().withErrorCode('INVALID_INPUT')
 *       .withMessage('Scenario name is required').send();
 *
 *   SmokeTestApiResponse.success200()
 *       .withBody(new SmokeTestApiResponse.RunAcknowledgment(execId, 'in_progress')).send();
 *
 * Every response includes X-API-Version and Content-Type headers.
 * Error responses include a structured JSON body with errorCode, message,
 * referenceId, and timestamp — never stack traces or internal details (OWASP A10).
 * 429 responses include a Retry-After header.
 */
public with sharing class SmokeTestApiResponse {

    @TestVisible private static final String  API_VERSION  = 'v1';
    private static final String  CONTENT_TYPE = 'application/json;charset=UTF-8';
    private static final Integer MAX_MSG_LEN  = 5000;

    // ─── Custom exception ─────────────────────────────────────────────────────
    public class IllegalStateException extends Exception {}

    // ─── Error body ───────────────────────────────────────────────────────────

    /** Structured error response body — all four fields always populated before send(). */
    public class ApiErrorBody {
        public String errorCode;
        public String message;
        public String referenceId;
        public String timestamp;

        @TestVisible
        ApiErrorBody() {
            this.referenceId = generateReferenceId();
            this.timestamp   = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
    }

    // ─── Success body shapes ─────────────────────────────────────────────────
    // Callers instantiate these and pass them to withBody(). Fields map directly
    // to the JSON contract defined in API Contracts.

    /** /v1/run acknowledgment payload. */
    public class RunAcknowledgment {
        public String executionId;
        public String status;
        public String timestamp;

        public RunAcknowledgment(String executionId, String status) {
            this.executionId = executionId;
            this.status      = status;
            this.timestamp   = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
    }

    /** A single scenario result nested in ExecutionStatus and ExecutionResults. */
    public class ScenarioResult {
        public String  name;
        public String  result;
        public Integer durationMs;
        public String  errorDetail;
    }

    /** /v1/status polling payload. */
    public class ExecutionStatus {
        public String               executionId;
        public String               status;
        public List<ScenarioResult> scenarios;
        public Long                 executionDurationMs;
    }

    /** Metadata integrity check summary nested in ExecutionResults. */
    public class MetadataIntegrity {
        public String       status;
        public List<Object> checks;
    }

    /** /v1/results full results payload. */
    public class ExecutionResults {
        public String               executionId;
        public String               status;
        public List<ScenarioResult> scenarios;
        public Decimal              securityHealthScore;
        public MetadataIntegrity    metadataIntegrity;
        public Long                 executionDurationMs;
        public String               timestamp;
    }

    // ─── Builder state ────────────────────────────────────────────────────────

    private Integer statusCode;
    private Boolean isError;
    private Object  bodyPayload;
    private Integer retryAfterSeconds;

    // ─── Private constructor ─────────────────────────────────────────────────

    private SmokeTestApiResponse(Integer code, Boolean isError) {
        this.statusCode = code;
        this.isError    = isError;
        if (isError) {
            this.bodyPayload = new ApiErrorBody();
        }
    }

    // ─── Static factory methods ───────────────────────────────────────────────

    public static SmokeTestApiResponse success200() { return new SmokeTestApiResponse(200, false); }
    public static SmokeTestApiResponse success201() { return new SmokeTestApiResponse(201, false); }
    public static SmokeTestApiResponse error400()   { return new SmokeTestApiResponse(400, true);  }
    public static SmokeTestApiResponse error401()   { return new SmokeTestApiResponse(401, true);  }
    public static SmokeTestApiResponse error403()   { return new SmokeTestApiResponse(403, true);  }
    public static SmokeTestApiResponse error404()   { return new SmokeTestApiResponse(404, true);  }
    public static SmokeTestApiResponse error429()   { return new SmokeTestApiResponse(429, true);  }
    public static SmokeTestApiResponse error500()   { return new SmokeTestApiResponse(500, true);  }

    // ─── Fluent builder methods ───────────────────────────────────────────────

    /**
     * Sets the errorCode field on the error body.
     * Defaults to 'UNKNOWN_ERROR' if null or empty.
     */
    public SmokeTestApiResponse withErrorCode(String code) {
        if (isError) {
            ((ApiErrorBody)bodyPayload).errorCode =
                (code != null && code.length() > 0) ? code : 'UNKNOWN_ERROR';
        }
        return this;
    }

    /**
     * Sets the message field, running the message through PII masking
     * and stack trace stripping. Truncates at 5,000 chars with '[TRUNCATED]'.
     * Defaults to a generic message if null or empty.
     */
    public SmokeTestApiResponse withMessage(String msg) {
        if (isError) {
            ApiErrorBody errBody = (ApiErrorBody)bodyPayload;
            String safe = sanitizeErrorMessage(msg);
            if (safe == null || safe.length() == 0) {
                safe = 'An unexpected error occurred. Reference ID: ' + errBody.referenceId;
            } else if (safe.length() > MAX_MSG_LEN) {
                safe = safe.left(MAX_MSG_LEN) + '[TRUNCATED]';
            }
            errBody.message = safe;
        }
        return this;
    }

    /**
     * Sets the response body for success responses.
     * Callers provide a typed inner class instance (RunAcknowledgment, ExecutionStatus,
     * ExecutionResults) or any serializable Object.
     */
    public SmokeTestApiResponse withBody(Object payload) {
        if (!isError) {
            this.bodyPayload = payload;
        }
        return this;
    }

    /**
     * Configures the Retry-After header value (seconds) for 429 responses.
     */
    public SmokeTestApiResponse withRetryAfter(Integer seconds) {
        this.retryAfterSeconds = seconds;
        return this;
    }

    // ─── send() ───────────────────────────────────────────────────────────────

    /**
     * Writes the response to RestContext.response: status code, all headers,
     * and the JSON-serialized body. Must be called within a @RestResource context.
     *
     * @throws SmokeTestApiResponse.IllegalStateException if RestContext.response is null.
     */
    public void send() {
        if (RestContext.response == null) {
            throw new IllegalStateException(
                'SmokeTestApiResponse.send() must be called within a @RestResource context. ' +
                'RestContext.response is null.'
            );
        }

        RestResponse res = RestContext.response;
        res.statusCode = this.statusCode;
        res.addHeader('X-API-Version', API_VERSION);
        res.addHeader('Content-Type',  CONTENT_TYPE);

        if (this.statusCode == 429 && this.retryAfterSeconds != null) {
            res.addHeader('Retry-After', String.valueOf(this.retryAfterSeconds));
        }

        // Guarantee all four error fields are non-null before serialization
        if (isError) {
            ApiErrorBody errBody = (ApiErrorBody)bodyPayload;
            if (errBody.errorCode == null || errBody.errorCode.length() == 0) {
                errBody.errorCode = 'UNKNOWN_ERROR';
            }
            if (errBody.message == null || errBody.message.length() == 0) {
                errBody.message = 'An unexpected error occurred. Reference ID: ' + errBody.referenceId;
            }
        }

        // Ensure success responses without an explicit body return an empty object
        Object toSerialize = (bodyPayload != null) ? bodyPayload : new Map<String, Object>();

        try {
            String jsonStr = JSON.serialize(toSerialize);
            res.responseBody = Blob.valueOf(jsonStr);
        } catch (Exception ex) {
            String refId = isError
                ? ((ApiErrorBody)bodyPayload).referenceId
                : generateReferenceId();
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf(
                '{"errorCode":"SERIALIZATION_ERROR","referenceId":"' + refId + '"}'
            );
            System.debug(LoggingLevel.ERROR,
                'SmokeTestApiResponse serialization failed [refId=' + refId + ']: ' +
                ex.getMessage());
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    /** Generates a 32-character lowercase hex string for support correlation. */
    @TestVisible
    private static String generateReferenceId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
    }

    /**
     * Strips Apex stack trace frames and optionally applies PII masking before
     * the message is included in an error response body.
     */
    @TestVisible
    private static String sanitizeErrorMessage(String msg) {
        if (msg == null) { return null; }
        String result = msg;
        // Optional PII masking — graceful degradation if ErrorSanitizer unavailable
        try {
            result = ErrorSanitizer.sanitize(result);
        } catch (Exception ignored) { }
        // Strip Apex stack trace patterns to prevent leaking class names / line numbers
        result = result.replaceAll('Class\\.[A-Za-z][^\\n]*', '[STACK_FRAME_REMOVED]');
        result = result.replaceAll('Trigger\\.[A-Za-z][^\\n]*', '[STACK_FRAME_REMOVED]');
        result = result.replaceAll('at line \\d+[^\\n]*', '[STACK_FRAME_REMOVED]');
        return result;
    }
}
