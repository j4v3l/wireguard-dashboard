# Contributing to Wireguard Dashboard Docker

Thank you for considering contributing to the Wireguard Dashboard Docker project!

## How to Contribute

1. Fork the repository
2. Create a new branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test your changes
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin feature/your-feature`)
7. Create a new Pull Request

## Development Environment

### Prerequisites

- Docker
- Docker Compose

### Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/wireguard-dashboard.git
   cd wireguard-dashboard
   ```

2. Build the Docker image:

   ```bash
   docker build -t wireguard-dashboard:dev .
   ```

3. Run the container:

   ```bash
   docker-compose up -d
   ```

## Testing

Before submitting a Pull Request, please test your changes locally:

1. Ensure the Docker image builds successfully
2. Verify that Wireguard is running correctly
3. Test the WGDashboard web interface
4. Check that all environment variables work as expected

## Code Style

- Follow the existing code style
- Comment your code where appropriate
- Keep changes focused and minimal

## Branching Strategy

- `main` branch is for stable releases
- `dev` branch is for active development
- Feature branches should be created from and merged back into `dev`

## Releasing

The CI/CD pipeline will automatically build and publish Docker images based on:

- Commits to `main` will update the `latest` tag
- Commits to `dev` will update the `beta` tag
- Tags in the format `vX.Y.Z` will create new version tags and update the `stable` tag

## Questions

If you have any questions, feel free to open an issue or discussion on GitHub.
