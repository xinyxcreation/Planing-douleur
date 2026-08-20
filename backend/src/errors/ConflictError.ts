import { ApiError } from './ApiError.js';

export class ConflictError extends ApiError {

    constructor(
        message = 'Conflit.'
    ) {

        super(
            409,
            'CONFLICT',
            message
        );

    }

}
