/**
 * Maps Prisma client errors to appropriate HTTP AppError subclasses.
 *
 * Prisma error codes reference:
 * https://www.prisma.io/docs/reference/api-reference/error-reference#error-codes
 */

import { Prisma } from '@prisma/client';
import {
  AppError,
  BadRequestError,
  ConflictError,
  InternalServerError,
  NotFoundError,
} from './http-errors.js';

/**
 * Converts a Prisma error (or any thrown value) into an `AppError` subclass.
 * Non-Prisma errors that are already `AppError` instances are returned unchanged.
 * Everything else is wrapped in `InternalServerError`.
 */
export function mapPrismaError(error: unknown): AppError {
  // Already an application error — pass through.
  if (error instanceof AppError) return error;

  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    switch (error.code) {
      case 'P2002': {
        // Unique constraint violation
        const target = Array.isArray(error.meta?.['target'])
          ? (error.meta['target'] as string[]).join(', ')
          : String(error.meta?.['target'] ?? 'unknown field');
        return new ConflictError(
          `A record with that value already exists (unique constraint on: ${target})`,
          'UNIQUE_CONSTRAINT_VIOLATION',
        );
      }

      case 'P2025':
        // Record required for the operation not found
        return new NotFoundError(
          error.meta?.['cause'] !== undefined
            ? String(error.meta['cause'])
            : 'Record not found',
        );

      case 'P2003': {
        // Foreign key constraint failure
        const field = String(error.meta?.['field_name'] ?? 'unknown field');
        return new BadRequestError(
          `Foreign key constraint failed on field: ${field}`,
          'FOREIGN_KEY_CONSTRAINT_FAILED',
        );
      }

      case 'P2000':
        // Input value too long for column
        return new BadRequestError('Input value exceeds the maximum allowed length', 'VALUE_TOO_LONG');

      case 'P2016':
        // Query interpretation error
        return new BadRequestError('Invalid query parameters', 'INVALID_QUERY');

      case 'P2014':
        // Relation violation
        return new BadRequestError('Invalid relation in request', 'RELATION_VIOLATION');

      default:
        return new InternalServerError(`Database error (Prisma ${error.code})`);
    }
  }

  if (error instanceof Prisma.PrismaClientValidationError) {
    return new BadRequestError('Database query validation failed', 'DB_VALIDATION_ERROR');
  }

  if (error instanceof Prisma.PrismaClientInitializationError) {
    return new InternalServerError('Database connection could not be established');
  }

  // Unknown error — wrap in InternalServerError.
  const message =
    error instanceof Error ? error.message : 'An unexpected database error occurred';
  return new InternalServerError(message);
}
