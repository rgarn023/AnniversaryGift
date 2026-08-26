import { jsonResponse } from "./cors.ts";

export class AppError extends Error {
  status: number;
  code: string;

  constructor(code: string, message: string, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export function errorResponse(err: unknown): Response {
  if (err instanceof AppError) {
    return jsonResponse(
      { error: { code: err.code, message: err.message } },
      err.status,
    );
  }

  console.error("Unhandled error:", err);
  return jsonResponse(
    {
      error: {
        code: "internal_error",
        message: "Something went wrong. Please try again.",
      },
    },
    500,
  );
}

export function requireFields(
  body: object,
  fields: string[],
): void {
  const record = body as Record<string, unknown>;
  for (const field of fields) {
    const value = record[field];
    if (value === undefined || value === null || value === "") {
      throw new AppError(
        "missing_field",
        `Missing required field: ${field}`,
        400,
      );
    }
  }
}
