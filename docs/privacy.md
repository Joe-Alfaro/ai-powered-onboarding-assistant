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

## Consent withdrawal

- A user can withdraw consent at any time. An upload in progress re-checks consent just before
  it saves its draft, so it saves nothing and deletes its image if consent was withdrawn.
