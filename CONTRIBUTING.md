# Contributing to Guacamole Docker Compose

First off, thank you for considering contributing to this project! It's people like you that make this project such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our commitment to be respectful and professional.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps to reproduce the problem**
* **Provide specific examples** to demonstrate the steps
* **Describe the behavior you observed** and what you expected
* **Include logs** from Docker containers if relevant
* **Specify your environment** (OS, Docker version, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a detailed description** of the suggested enhancement
* **Explain why this enhancement would be useful**
* **List any relevant examples** from other projects if applicable

### Pull Requests

* Fill in the required template
* Follow the existing code style
* Include appropriate tests if applicable
* Update documentation as needed
* End all files with a newline

## Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/guacamole-docker-compose.git
   cd guacamole-docker-compose
   ```

3. Create a branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. Make your changes and test:
   ```bash
   ./prepare.sh
   docker compose up -d
   # Test your changes
   ```

5. Commit your changes:
   ```bash
   git add .
   git commit -m "Add some feature"
   ```

6. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

7. Open a Pull Request

## Testing Checklist

Before submitting a pull request, ensure:

- [ ] Fresh installation works with `./prepare.sh && docker compose up -d`
- [ ] SSL certificate generation works (test with staging)
- [ ] All containers start successfully
- [ ] Guacamole web interface is accessible
- [ ] Documentation is updated if needed
- [ ] No sensitive information is committed

## Styleguides

### Git Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

### Documentation

* Use Markdown for documentation
* Keep README.md up to date
* Add inline comments for complex configurations
* Include examples where helpful

## Additional Notes

### Issue and Pull Request Labels

* `bug` - Something isn't working
* `enhancement` - New feature or request
* `documentation` - Documentation improvements
* `good first issue` - Good for newcomers
* `help wanted` - Extra attention is needed

Thank you for contributing! 🎉
