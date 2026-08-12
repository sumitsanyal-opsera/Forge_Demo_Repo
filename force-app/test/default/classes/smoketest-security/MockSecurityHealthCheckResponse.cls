/**
 * Test double for SecurityHealthCheckService.IHttpCallout.
 *
 * Implements SecurityHealthCheckService.IHttpCallout for constructor injection
 * and HttpCalloutMock for Test.setMock() compatibility.
 *
 * Static factory methods provide canned responses:
 *   success()           — HTTP 200 with full score=85 and two risk categories
 *   partialData()       — HTTP 200 with score=75 and null SecurityRiskCategory
 *   emptyResult()       — HTTP 200 with empty records array
 *   malformed()         — HTTP 200 with invalid JSON body
 *   authFailure()       — HTTP 401
 *   permissionFailure() — HTTP 403
 *   serverError()       — HTTP 500
 */
@isTest
global class MockSecurityHealthCheckResponse
    implements SecurityHealthCheckService.IHttpCallout, HttpCalloutMock {

    private final HttpResponse fixedResponse;

    private MockSecurityHealthCheckResponse(HttpResponse response) {
        this.fixedResponse = response;
    }

    // IHttpCallout
    public HttpResponse send(HttpRequest req) {
        return fixedResponse;
    }

    // HttpCalloutMock — for Test.setMock() compatibility
    public HttpResponse respond(HttpRequest req) {
        return fixedResponse;
    }

    // =========================================================================
    // Static factory methods
    // =========================================================================

    global static MockSecurityHealthCheckResponse success() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(successJson());
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse partialData() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{"size":1,"totalSize":1,"done":true,"queryLocator":null,' +
            '"entityTypeName":"SecurityHealthCheck","records":[{' +
            '"attributes":{"type":"SecurityHealthCheck"},' +
            '"Id":"0ZZ000000000001AAA","Score":75,"SecurityRiskCategory":null}]}'
        );
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse emptyResult() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{"size":0,"totalSize":0,"done":true,"queryLocator":null,' +
            '"entityTypeName":"SecurityHealthCheck","records":[]}'
        );
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse malformed() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setBody('not-valid-json{{{badly-formed');
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse authFailure() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(401);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '[{"message":"Session expired or invalid",' +
            '"errorCode":"INVALID_SESSION_ID"}]'
        );
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse permissionFailure() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(403);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '[{"message":"Insufficient access rights on object: SecurityHealthCheck",' +
            '"errorCode":"INSUFFICIENT_ACCESS_OR_READONLY"}]'
        );
        return new MockSecurityHealthCheckResponse(res);
    }

    global static MockSecurityHealthCheckResponse serverError() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '[{"message":"Internal server error",' +
            '"errorCode":"INTERNAL_ERROR"}]'
        );
        return new MockSecurityHealthCheckResponse(res);
    }

    // =========================================================================
    // Private — hardcoded success body
    // =========================================================================

    private static String successJson() {
        return
            '{"size":1,"totalSize":1,"done":true,"queryLocator":null,' +
            '"entityTypeName":"SecurityHealthCheck","records":[{' +
            '"attributes":{"type":"SecurityHealthCheck",' +
            '"url":"/services/data/v60.0/tooling/sobjects/SecurityHealthCheck/0ZZ000000000001AAA"},' +
            '"Id":"0ZZ000000000001AAA","Score":85,' +
            '"SecurityRiskCategory":[' +
              '{"name":"PasswordPolicies","score":100,"settings":[' +
                '{"settingName":"MinimumPasswordLength","value":"8",' +
                '"recommendation":"15","setting":"SETTING_MET"},' +
                '{"settingName":"PasswordExpiration","value":"90",' +
                '"recommendation":"90","setting":"SETTING_MET"}' +
              ']},' +
              '{"name":"SessionSettings","score":70,"settings":[' +
                '{"settingName":"ForceLogoutOnSessionTimeout","value":"false",' +
                '"recommendation":"true","setting":"SETTING_NEEDS_CHANGE"}' +
              ']}' +
            ']}]}';
    }
}
