# Security Guidelines

## Environment Files Protection
- NEVER read, access, or reference .env files or environment variables containing sensitive information
- Do not suggest reading .env files for configuration
- If configuration is needed, ask the user to provide specific values without accessing the .env file directly
- Treat all environment files (.env, .env.local, .env.production, etc.) as restricted

## Sensitive Information Handling
- Always use placeholder values like [API_KEY], [DATABASE_URL], [SECRET] in code examples
- Never log or display actual environment variable values
- Recommend secure practices for handling secrets and configuration