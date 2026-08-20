import { ApiError } from './ApiError.js';

export class NotFoundError extends ApiError {

    constructor(
        message = 'Ressource introuvable.'
    ) {

        super(
            404,
            'NOT_FOUND',
            message
        );

    }

}
