# Data retention and deletion

What happens to the ID image and the identity details a user gives during onboarding (R17).

## ID images

- An image is uploaded only after the user agrees to the consent text, and the consent version
  they saw is recorded with the time (R12).
- The image is checked by its content, and the uploaded filename is thrown away. HEIC photos are
  converted to JPEG, without their metadata, before they are stored.
- Images are kept in a private Storage bucket. The app reaches it with a server-only key, and the
  browser sees an image only through a signed URL that expires after 60 seconds. There is no
  public URL.
- The image is deleted as soon as the user confirms their details, or types them in by hand.
- An image whose details are never confirmed is deleted, with its draft, by an hourly job once it
  is **1 hour** old. At most it lives just under 2 hours.

## Identity details

- What OCR reads is kept only as a draft on the upload, and only the full name, date of birth and
  address (each with how confident OCR was). Nothing else on the card is stored.
- The details are saved to the user's onboarding record only when the user confirms them, as
  they confirmed them. The draft is then cleared.
- Identity details, drafts and chat content are encrypted in the database.

## Consent withdrawal and account deletion

A user can withdraw consent (`DELETE /consents`) or delete their account (`DELETE /account`) from
the app at any time (R13). Both act only on the signed-in user, take effect in the request, and
are safe to repeat.

- **Processing stops first.** Consent is revoked before anything is deleted. An upload in
  progress re-checks consent just before it saves its draft, so it saves nothing and deletes its
  image. Chat checks consent before every LLM call, so later messages get a refusal and make no
  LLM call.
- **Hard deletion.** Both delete, as rows rather than flags: the onboarding record with the
  confirmed identity, every upload with its draft, the images in Storage, the conversation, its
  messages and the assessment. Deleting an image also kills any signed URL issued for it, and
  requests for the deleted document return not found. If Storage can't delete an image, nothing
  is deleted and the request fails, so a retry starts again from the same data.
- **Withdrawal keeps the account.** The person can still sign in and type their details by hand.
  Their bookings are kept, because a slot hold isn't personal data.
- **Deletion removes the account.** It also cancels an active booking (freeing the slot for
  others), deletes every booking row for the user, and deletes the sign-in account.
- **What stays.** The user's revoked consent records (consent text version and times), so a
  sign-in token that hasn't expired yet still can't restart processing.

## Audit

Each withdrawal and deletion writes one audit entry holding only a pseudonymous reference (a
keyed HMAC of the user ID, which can't be reversed by hashing guessed IDs), the action
(`consent_withdrawn` or `account_deleted`) and the time. It holds no name, email, user ID or other
personal data. Admin access is audited the same way (R19).
