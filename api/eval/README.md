# AI eval

## OCR golden set (R26)

`eval/golden/` holds 30 synthetic ID images and `labels.json`. Regenerate them with:

```sh
eval/generate_golden_set --out eval/golden
```

The generator is seeded, so `labels.json` comes out the same on every run.

Every document is made up. Names are invented. Every address uses the state code `ZZ`, which
isn't a real state, and a ZIP code starting with `000`, which isn't assigned.

`labels.json` is an array with one object per image:

| Key | Type | Meaning |
| --- | --- | --- |
| `id` | string | Unique id, for example `"007"` |
| `image` | string | File name inside `eval/golden/` |
| `category` | string | `clean`, `phone_photo`, `skew` or `glare` |
| `hard` | boolean | `true` for a hard near-miss case |
| `hard_reason` | string or null | Why the case is hard. Required when `hard` is `true` |
| `expected` | object | `full_name`, `date_of_birth` (`YYYY-MM-DD`) and `address` |

### Latest OCR results

Tesseract 5.5.3 (leptonica 1.87.0) with libvips 8.18.7, on an Apple M2 running macOS 26.6:

| Field | All documents (30) | Hard cases (6) |
| --- | --- | --- |
| full_name | 96.7% | 83.3% |
| date_of_birth | 100.0% | 100.0% |
| address | 100.0% | 100.0% |

The one miss is case 027 (strong glare): Tesseract reads `LENA N` as `LENAN`.

## Scoring OCR

```sh
bin/rake ai:eval:ocr
```

This runs `Ocr::Extractor` and `Ocr::FieldMapper` on every golden image and prints the accuracy of
each field, first over all documents and then over the hard cases only. Set `GOLDEN_DIR` to score a
different directory with the same layout.

Field-level accuracy for a field is the number of documents where that field matches, divided by
the number of documents.

### Field-level match

A field matches when the normalized read value equals the normalized expected value. A field the
OCR didn't read (`nil`) never matches. `Eval::FieldMatch` implements exactly these rules, and its
spec checks every example in the table below.

Rules for every field, applied first:

1. Unicode NFKC normalization, then lowercase.
2. Leading and trailing whitespace is removed, and every run of whitespace becomes one space.

`full_name`:

3. Periods and commas are removed. Hyphens and apostrophes are kept. Word order isn't changed, so
   `Sample, Jane` doesn't match `Jane Sample`.

`date_of_birth`: both values are parsed into a calendar date, and the dates are compared. These
formats are accepted, with month names in any case:

4. `YYYY-MM-DD`.
5. `MM/DD/YYYY` and `MM-DD-YYYY`, with or without leading zeros. Numeric dates are always read
   month first.
6. `DD MON YYYY` and `MON DD YYYY`, with an optional comma after the day, where `MON` is a full
   month name or its three-letter abbreviation.
7. Anything else, including two-digit years and impossible dates such as `02/30/1985`, can't be
   parsed and never matches.

`address`:

8. Periods are removed and commas become spaces (then whitespace is collapsed again).
9. These whole words are replaced by their abbreviation: `street` → `st`, `avenue` → `ave`,
   `road` → `rd`, `boulevard` → `blvd`, `drive` → `dr`, `lane` → `ln`, `court` → `ct`,
   `place` → `pl`, `apartment` → `apt`, `suite` → `ste`, `north` → `n`, `south` → `s`,
   `east` → `e`, `west` → `w`.

Nothing else is normalized. Digits must match exactly, so `128 Fake St` doesn't match
`123 Fake St`, and OCR confusions such as `O` for `0` count as misses.

### Match examples

| Field | Expected | Read | Match |
| --- | --- | --- | --- |
| full_name | Jane Q Sample | JANE Q SAMPLE | yes |
| full_name | Jane Q Sample | `  jane   q  sample ` | yes |
| full_name | Jane Q. Sample | Jane Q Sample | yes |
| full_name | Mary-Ann O'Testcase | MARY-ANN O'TESTCASE | yes |
| full_name | Mary-Ann O'Testcase | Mary Ann OTestcase | no |
| full_name | Jane Sample | Sample, Jane | no |
| full_name | Jane Sample | Jane Sampel | no |
| date_of_birth | 1985-03-14 | 03/14/1985 | yes |
| date_of_birth | 1985-03-14 | 3/14/1985 | yes |
| date_of_birth | 1985-03-14 | 03-14-1985 | yes |
| date_of_birth | 1985-03-14 | 14 MAR 1985 | yes |
| date_of_birth | 1985-03-14 | March 14, 1985 | yes |
| date_of_birth | 1985-03-04 | 04/03/1985 | no |
| date_of_birth | 1985-03-14 | 03/14/85 | no |
| date_of_birth | 1985-03-14 | 1985-03-15 | no |
| address | 123 Fake St, Springfield, ZZ 00000 | 123 FAKE STREET SPRINGFIELD ZZ 00000 | yes |
| address | 45 North Example Ave Apt 2, Testville, ZZ 00012 | 45 N. Example Avenue Apartment 2 Testville ZZ 00012 | yes |
| address | 9 West Placeholder Blvd, Mocktown, ZZ 00031 | 9 W PLACEHOLDER BOULEVARD, MOCKTOWN, ZZ 00031 | yes |
| address | 123 Fake St, Springfield, ZZ 00000 | 128 Fake St, Springfield, ZZ 00000 | no |
| address | 123 Fake St, Springfield, ZZ 00000 | 123 Fake St, Springfield, ZZ OOOOO | no |
| address | 123 Fake St, Springfield, ZZ 00000 | 123 Fake St | no |

