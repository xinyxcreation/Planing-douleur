import { ApiError } from './ApiError.js';

export class ValidationError extends ApiError {

    constructor(
        message = 'Validation invalide.'
    ) {

        super(
            422,
            'VALIDATION_ERROR',
            message
        );

    }

}
