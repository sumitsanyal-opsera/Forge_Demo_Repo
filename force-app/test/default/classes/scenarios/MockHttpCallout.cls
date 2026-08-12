/**
 * Configurable HttpCalloutMock for unit testing HTTP-based scenario classes.
 *
 * Usage — normal response:
 *   Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, responseBody));
 *
 * Usage — simulate CalloutException (network failure / timeout):
 *   Test.setMock(HttpCalloutMock.class, MockHttpCallout.throwingCallout('Connection timeout'));
 */
@isTest
public class MockHttpCallout implements HttpCalloutMock {

    private Integer statusCode;
    private String  body;
    private Boolean shouldThrow  = false;
    private String  throwMessage = null;

    /** Normal response mock — returns the given status code and body. */
    public MockHttpCallout(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body       = (body != null) ? body : '';
    }

    /** Factory for a mock that throws CalloutException to simulate network/timeout errors. */
    public static MockHttpCallout throwingCallout(String message) {
        MockHttpCallout m = new MockHttpCallout(0, null);
        m.shouldThrow  = true;
        m.throwMessage = message;
        return m;
    }

    // =========================================================================

    public HttpResponse respond(HttpRequest req) {
        if (shouldThrow) {
            CalloutException ce = new CalloutException();
            ce.setMessage(throwMessage != null ? throwMessage : 'Mock callout exception');
            throw ce;
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(body != null ? body : '');
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
}
