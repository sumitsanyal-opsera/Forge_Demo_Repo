public class ChecklistResult {

    public enum Status { PASS, FAIL, WARNING }

    public String checkName;
    public String checkType;
    public Status status;
    public String expectedValue;
    public String actualValue;
    public String detail;

    public ChecklistResult(
        String checkName,
        String checkType,
        Status status,
        String expectedValue,
        String actualValue,
        String detail
    ) {
        this.checkName     = checkName;
        this.checkType     = checkType;
        this.status        = status;
        this.expectedValue = expectedValue;
        this.actualValue   = actualValue;
        this.detail        = detail;
    }
}
