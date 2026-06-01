import * as functions from 'firebase-functions';
import { randomUUID } from 'crypto';

import { admin } from '../firebase';

const PROFILE_IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const PROFILE_IMAGE_EXTENSIONS: Record<string, string> = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
};

export interface ProfilePhotoUploadData {
    base64: string;
    contentType: string;
    extension?: string;
}

export async function uploadProfilePhoto(
    uid: string,
    upload: ProfilePhotoUploadData | null | undefined,
    folder = 'user_photos'
): Promise<string | undefined> {
    if (!upload) return undefined;
    if (typeof upload.base64 !== 'string' || typeof upload.contentType !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Invalid profile photo upload.'
        );
    }

    const expectedExtension = PROFILE_IMAGE_EXTENSIONS[upload.contentType];
    if (!expectedExtension) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Profile photo must be a JPEG, PNG, or WebP image.'
        );
    }

    const buffer = Buffer.from(upload.base64, 'base64');
    if (buffer.length === 0 || buffer.length > PROFILE_IMAGE_MAX_BYTES) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Profile photo must be less than 5 MB.'
        );
    }

    const requestedExtension = (upload.extension || expectedExtension)
        .toLowerCase()
        .replace(/^\./, '');
    const extension = requestedExtension === expectedExtension ||
        (expectedExtension === 'jpg' && requestedExtension === 'jpeg')
        ? expectedExtension
        : expectedExtension;
    const bucket = admin.storage().bucket();
    const token = randomUUID();
    const file = bucket.file(`${folder}/${uid}.${extension}`);

    await file.save(buffer, {
        resumable: false,
        metadata: {
            contentType: upload.contentType,
            cacheControl: 'public, max-age=31536000',
            metadata: {
                firebaseStorageDownloadTokens: token,
            },
        },
    });

    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`;
}

export async function deleteProfilePhotos(uid: string, folder = 'user_photos'): Promise<void> {
    const bucket = admin.storage().bucket();
    await Promise.all(
        ['jpg', 'jpeg', 'png', 'webp'].map((extension) =>
            bucket
                .file(`${folder}/${uid}.${extension}`)
                .delete({ ignoreNotFound: true })
                .catch((error) => {
                    console.warn(`Failed to delete profile photo ${uid}.${extension}:`, error);
                })
        )
    );
}
