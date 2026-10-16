import { ApiError } from './client'

// The client only throws ApiError; anything else is treated as a retryable
// failure so a form can always show a message.
export function toApiError(error: unknown) {
  if (error instanceof ApiError) return error
  return new ApiError({
    status: null,
    code: 'unexpected',
    message: 'Something went wrong. Please try again.',
    actions: ['retry'],
  })
}
