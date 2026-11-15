# Privacy disclosure — release draft

CloudPocket hosts a file-sharing server on the user's device. Selected files are served to people who can reach the session and pass configured admission checks. Public tunnels expose a reachable internet endpoint; local mode requires an appropriate local network.

File transfers are streamed. Received files remain on the host's configured storage until deleted by the user. File-sharing history and preferences may persist locally. Temporary room messages and participant state remain in process memory; room media is held in an app cache sandbox and removed during room cleanup. Operating-system file deletion does not guarantee physical erasure or removal from backups, recipient copies, screenshots, or modified clients.

Optional services receive data required for their function: Cloudflare/LocalTunnel/Bore carry tunnel traffic; ntfy.sh discovery receives a public Chat ID mapping, tunnel URL, room name when provided, and registration timing. Discovery requires a PIN and excludes PINs and invite tokens. Google sign-in, when configured, loads Google's sign-in client and verifies tokens with Google. Consult each provider's current policies before enabling that service.

HTTPS protects transport to its terminating endpoint. CloudPocket's current room key exchange does not establish secrecy from the transport relay. Bore and local HTTP lack transport encryption. Local-browser plaintext chat is permitted only for local HTTP addresses and displays a warning when WebCrypto is unavailable; public HTTP plaintext chat is blocked. Browsers cannot prevent screenshots or copying by a determined recipient.

Release owner must add a real contact and publication location, verify third-party disclosures against the release configuration, and complete the applicable store Data safety form. This draft is not yet a published policy.
