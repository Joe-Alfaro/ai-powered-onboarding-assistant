import type { Assessment } from './chatApi'

interface AssessmentSummaryProps {
  assessment: Assessment
}

export function AssessmentSummary({ assessment }: AssessmentSummaryProps) {
  return (
    <section aria-labelledby="assessment-summary-heading">
      <h2 id="assessment-summary-heading">Assessment summary</h2>
      <dl>
        <dt>Reason</dt>
        <dd>{assessment.reason}</dd>
        <dt>Urgency</dt>
        <dd>{assessment.urgency}</dd>
        <dt>Preferred window</dt>
        <dd>{assessment.preferred_window}</dd>
        {assessment.notes && (
          <>
            <dt>Notes</dt>
            <dd>{assessment.notes}</dd>
          </>
        )}
      </dl>
    </section>
  )
}
