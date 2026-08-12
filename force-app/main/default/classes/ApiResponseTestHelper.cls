/**
 * Reusable test utilities for SmokeTestApiResponse and REST endpoint tests.
 *
 * Provides methods to deserialize response bodies, assert required field
 * presence on error responses, detect stack trace leakage, and read
 * response headers.
 */
@isTest
public class ApiResponseTestHelper {

    /**
     * Deserializes the response body JSON into an untyped map.
     * Fails the test if the body is null or not valid JSON.
     */
    public static Map<String, Object> deserializeErrorBody(RestResponse response) {
        System.assert(response.responseBody != null, 'Response body must not be null');
        String jsonStr = response.responseBody.toString();
        return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
    }

    /**
     * Asserts that a deserialized error body contains all four required fields
     * with non-null values: errorCode, message, referenceId, timestamp.
     */
    public static void assertErrorFields(Map<String, Object> body) {
        System.assert(body.containsKey('errorCode'),
            'Error body must contain errorCode field');
        System.assert(body.containsKey('message'),
            'Error body must contain message field');
        System.assert(body.containsKey('referenceId'),
            'Error body must contain referenceId field');
        System.assert(body.containsKey('timestamp'),
            'Error body must contain timestamp field');
        System.assert(body.get('errorCode')   != null, 'errorCode must not be null');
        System.assert(body.get('message')     != null, 'message must not be null');
        System.assert(body.get('referenceId') != null, 'referenceId must not be null');
        System.assert(body.get('timestamp')   != null, 'timestamp must not be null');
    }

    /**
     * Asserts that the response body string does not contain Apex stack trace
     * patterns ('Class.', 'Trigger.', 'at line') that would indicate leakage
     * of internal implementation details (OWASP A10).
     */
    public static void assertNoStackTrace(String responseBody) {
        System.assert(
            !responseBody.contains('Class.'),
            'Response body must not expose Apex class references (stack trace leak)'
        );
        System.assert(
            !responseBody.contains('Trigger.'),
            'Response body must not expose Trigger references (stack trace leak)'
        );
        System.assert(
            !responseBody.contains('at line'),
            'Response body must not expose "at line" patterns (stack trace leak)'
        );
    }

    /**
     * Returns the value of a named response header, or null if not present.
     * Header name lookup is case-sensitive (Salesforce stores headers as-set).
     */
    public static String getResponseHeader(RestResponse response, String headerName) {
        if (response.headers == null || !response.headers.containsKey(headerName)) {
            return null;
        }
        return response.headers.get(headerName);
    }

    /**
     * Initialises RestContext.request and RestContext.response for use in
     * unit tests that exercise code calling RestContext members.
     */
    public static void setUpRestContext() {
        RestRequest req        = new RestRequest();
        req.httpMethod         = 'GET';
        req.requestURI         = '/services/apexrest/v1/test';
        RestContext.request    = req;
        RestContext.response   = new RestResponse();
    }
}
