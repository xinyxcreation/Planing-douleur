import { ApiError } from './ApiError.js';

export class AuthorizationError extends ApiError {

    constructor(
        message = 'Accès refusé.'
    ) {

        super(
            403,
            'AUTHORIZATION_ERROR',
            message
        );

    }

}
