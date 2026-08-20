import { ApiError } from './ApiError.js';

export class AuthenticationError extends ApiError {

    constructor(
        message = 'Authentification échouée.'
    ) {

        super(
            401,
            'AUTHENTICATION_ERROR',
            message
        );

    }

}
