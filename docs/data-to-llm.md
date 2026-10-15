# Data sent to LLM providers

This document lists exactly which personal data the API sends to an LLM provider (R20). It applies
to every supported provider: Anthropic, Groq, Gemini and Ollama. The provider is chosen by
`LLM_PROVIDER`, with `LLM_FALLBACK_PROVIDER` tried once on a failure, and both receive the same
payload.

`Llm::PayloadBuilder` (`api/app/services/llm/payload_builder.rb`) builds the only payload that can
leave for an LLM. The adapters refuse anything else, and a contract spec
(`api/spec/services/llm/data_to_llm_contract_spec.rb`) captures the real request body sent to each
provider and checks that the personal-data fields in it match the table below exactly.

## Fields sent

| Field | What it is | Why it is needed |
| --- | --- | --- |
| `message_text` | The text of the user's recent chat messages and the assistant's replies, with known identity values replaced by placeholders. | The LLM reads the conversation to work out what the user wants (the intent), pick out assessment answers and write the next reply. Without it there is no chatbot. |
| `assessment_draft` | The assessment answers collected so far, limited to the fields the LLM is asked to fill: reason for seeking the service, urgency, preferred appointment window, distress flag and free-text notes. Identity values in them are replaced by placeholders. | The LLM needs to know which answers it already has so it asks for the next missing one and doesn't ask twice. |

The system prompt and the response schema are also sent. They are fixed text written by us and
contain no personal data.

## Never sent

| Data | How it is kept out |
| --- | --- |
| Full name | Replaced by `[NAME]` in every message and draft value, as the whole name or any single part of it, in any letter case. |
| Date of birth | Replaced by `[DATE_OF_BIRTH]` when written as ISO (`1987-03-14`), US or day-first numeric (`3/14/1987`, `14/03/1987`) or with the month in words (`March 14, 1987`, `14 March 1987`). |
| Address | Replaced by `[ADDRESS]` when written in full or as the street line alone. |
| Email address, user ID and any other account data | Never passed to the payload builder; draft keys outside the assessment fields are dropped. |
| ID document images | No code path sends image bytes to an LLM. The builder accepts plain UTF-8 text only and rejects binary data, image data URIs and image content blocks. Images go only to the self-hosted OCR engine. |

Redaction covers the identity values the user has already confirmed. A value the user types
before it is known, or writes in a form the builder doesn't recognize (for example a misspelled
name), can still reach the provider inside `message_text`.

## Logging

LLM client debug logging is off in every environment. Request and response bodies are never
logged, and error messages name the provider and the HTTP status but never include a key or the
payload.
