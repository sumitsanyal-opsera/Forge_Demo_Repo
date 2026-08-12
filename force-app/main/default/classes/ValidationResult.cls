public class ValidationResult {

    public final Boolean isValid;
    public final List<String> errorMessages;

    public ValidationResult(Boolean isValid, List<String> errorMessages) {
        this.isValid       = isValid;
        this.errorMessages = errorMessages != null ? errorMessages : new List<String>();
    }
}
