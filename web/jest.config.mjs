import nextJest from 'next/jest.js'

const createJestConfig = nextJest({ dir: './' })

// Run every test as a browser outside UTC (R37). Jest gives each test file a
// copy of process.env, so a test can't change the zone itself; setting it
// here, before the workers start, is what reaches Date and Intl.
process.env.TZ = 'America/New_York'

/** @type {import('jest').Config} */
const config = {
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  // Playwright runs the end-to-end tests in e2e/ (npm run e2e).
  testPathIgnorePatterns: ['/node_modules/', '<rootDir>/e2e/'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    // The root layout only renders <html> and <body>; Playwright covers it.
    '!src/app/layout.tsx',
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80,
    },
  },
}

export default createJestConfig(config)
