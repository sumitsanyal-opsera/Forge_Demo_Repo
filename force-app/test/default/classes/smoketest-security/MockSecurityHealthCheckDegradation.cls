/**
 * Test double for SecurityHealthCheckService.IHttpCallout targeting degradation paths.
 *
 * Covers failure modes not already addressed by MockSecurityHealthCheckResponse:
 *   networkError()    — throws CalloutException to simulate network failure
 *   http500()         — HTTP 500 server error (updated message assertions)
 *   http403()         — HTTP 403 permission denied
 *   http401()         — HTTP 401 authentication failure
 *   malformedBody()   — HTTP 200 with non-parseable JSON body
 */
@isTest
global class MockSecurityHealthCheckDegradation
    implements SecurityHealthCheckService.IHttpCallout {

    private final Integer  statusCode;
    private final String   responseBody;
    private final Boolean  throwCalloutException;

    private MockSecurityHealthCheckDegradation(
        Integer statusCode,
        String  responseBody,
        Boolean throwCalloutException
    ) {
        this.statusCode            = statusCode;
        this.responseBody          = responseBody;
        this.throwCalloutException = throwCalloutException;
    }

    // IHttpCallout implementation
    public HttpResponse send(HttpRequest req) {
        if (throwCalloutException) {
            CalloutException ce = new CalloutException();
            ce.setMessage('Connection refused — remote host unreachable');
            throw ce;
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(responseBody != null ? responseBody : '');
        return res;
    }

    // =========================================================================
    // Static factory methods
    // =========================================================================

    /** Simulates a network-level failure (CalloutException). */
    global static MockSecurityHealthCheckDegradation networkError() {
        return new MockSecurityHealthCheckDegradation(0, null, true);
    }

    /** HTTP 500 — Tooling API server error. */
    global static MockSecurityHealthCheckDegradation http500() {
        return new MockSecurityHealthCheckDegradation(
            500,
            '[{"message":"Internal server error","errorCode":"INTERNAL_ERROR"}]',
            false
        );
    }

    /** HTTP 403 — integration user lacks View Setup and Configuration permission. */
    global static MockSecurityHealthCheckDegradation http403() {
        return new MockSecurityHealthCheckDegradation(
            403,
            '[{"message":"Insufficient access rights on object: SecurityHealthCheck",' +
            '"errorCode":"INSUFFICIENT_ACCESS_OR_READONLY"}]',
            false
        );
    }

    /** HTTP 401 — authentication / session failure. */
    global static MockSecurityHealthCheckDegradation http401() {
        return new MockSecurityHealthCheckDegradation(
            401,
            '[{"message":"Session expired or invalid","errorCode":"INVALID_SESSION_ID"}]',
            false
        );
    }

    /** HTTP 200 with a malformed JSON body. */
    global static MockSecurityHealthCheckDegradation malformedBody() {
        return new MockSecurityHealthCheckDegradation(
            200,
            '<<< NOT VALID JSON >>>',
            false
        );
    }
}
