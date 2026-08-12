export interface ValidationError {
  line: number;
  column: number;
  message: string;
}

export interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
}

// WO-095: flat string errors for file-path-based validation
export interface XmlValidationResult {
  isValid: boolean;
  errors: string[];
}
