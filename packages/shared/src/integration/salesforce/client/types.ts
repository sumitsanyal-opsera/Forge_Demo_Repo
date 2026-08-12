/**
 * Domain types for the Salesforce REST API client.
 */

/**
 * An individual Salesforce REST API error element.
 * Salesforce always returns errors as an array; one response body can carry
 * multiple error objects.
 */
export interface SalesforceErrorBody {
  errorCode: string;
  message: string;
  fields?: string[];
}

/**
 * Salesforce sObject record base type.
 * All sObject records include a top-level `attributes` envelope.
 * Callers should extend this with concrete field types for type safety.
 */
export interface SObjectRecord {
  attributes: {
    type: string;
    url: string;
  };
  Id?: string;
  [key: string]: unknown;
}

/**
 * Salesforce SOQL query result envelope.
 * A `done:false` result carries `nextRecordsUrl` for pagination via queryMore().
 */
export interface QueryResult<T extends SObjectRecord = SObjectRecord> {
  totalSize: number;
  done: boolean;
  records: T[];
  /** Present when `done === false`; path relative to the instanceUrl. */
  nextRecordsUrl?: string;
}

/** Configuration options for SalesforceApiClient. */
export interface SalesforceApiClientConfig {
  /**
   * Salesforce API version to use in all request URLs.
   * Defaults to the SF_API_VERSION env var, then v59.0.
   */
  apiVersion?: string;
  /** Injectable HTTP client for unit testing without real network calls. */
  httpClient?: (url: string, init: RequestInit) => Promise<Response>;
}
