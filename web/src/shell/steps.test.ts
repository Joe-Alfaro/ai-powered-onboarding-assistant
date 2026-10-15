import { STEPS, stepFromPath } from './steps'

describe('onboarding steps', () => {
  it('lists the steps in flow order with their routes', () => {
    expect(STEPS.map(({ id, path }) => [id, path])).toEqual([
      ['chat', '/chat'],
      ['identity', '/identity'],
      ['confirm', '/confirm'],
      ['schedule', '/schedule'],
      ['done', '/done'],
    ])
  })

  it('gives every step a human-readable label', () => {
    STEPS.forEach((step) => {
      expect(step.label.trim()).not.toBe('')
    })
  })

  it('finds the step for a route, including nested routes', () => {
    expect(stepFromPath('/schedule')).toBe('schedule')
    expect(stepFromPath('/identity/manual')).toBe('identity')
  })

  it('returns null for routes outside the flow', () => {
    expect(stepFromPath('/')).toBeNull()
    expect(stepFromPath('/chatroom')).toBeNull()
  })
})
