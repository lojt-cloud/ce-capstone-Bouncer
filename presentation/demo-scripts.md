Bouncer — Basic Demo Script

1. Intro

“This is Bouncer, my cloud engineering capstone.”
“The goal was to build a secure, scalable AWS application using Terraform and CI/CD.”
"little story telling with it (warmup)

2. Architecture

Show architecture diagram.
“Traffic comes through Route 53 and WAF.”
“The ALB terminates HTTPS and sends traffic to EC2 instances.”
“The app runs across three Availability Zones.”
“RDS stores the data.”
“Redis stores shared session and security state.”
“The database and application tiers are private.”

SHORT ROLES
Flask       = logic
PostgreSQL  = permanent data
Redis       = shared temporary state
Gunicorn    = runs/serves Flask
EC2         = machines running the application
ALB         = distributes traffic
WAF         = blocks bad/rate-abusive traffic before the app(Log4j/JNDI)
Route 53    = point users to my app's internet facing ALB



EACH ROLE AND JOB
postgre job: stores users(uname, bcrypt pw hashes), events(which event tickets are avaliable), tickets(who bought what), 
baked in schema.sql that creates tables IF they don't exist 
Redis is shared temporary app state. 
job: login lockout(counts, stores temporary lock)
     sessions(after login app use secure cookie based session, session state lives here)
     /buy raete limiting(tracks buy attempts)->gives protection to DB (app level 429 protection->DoS or bruteforce)
     needs shared state for the 3 app

Flask app: business logic layer
jobs:
/login 
username + password
        ↓
look up user in PostgreSQL
        ↓
bcrypt password check
        ↓
check/update Redis lockout state
        ↓
create session
        ↓
store session in Redis
        ↓
send secure cookie

/me 
session check 
browser sends its session cookie, app checks session state in redis
authenticated = true
username = ...

/buy
purchase logic
User
 ↓
/buy
 ↓
check authentication
 ↓
Redis rate-limit check
 ↓
insert ticket into PostgreSQL
 ↓
PostgreSQL unique constraint
 ↓
201 or 409

(redis rate limits /buy how fast user can attempt)
PostgreSQL: is user allowed to own another ticket?

/health 
app health endpoint, ALB uses to check EC2 instance is healthy to recieve traffic

Gunicorn: runs the app







3. Pipeline

briefly: branch protection 
CI checks: checkov, terraform fmt, nightly drift detection, layered check, terraform plan

Open https://app.projectbouncer.org
Show /health.
Log in with demo user.
Show authenticated /me.

4. Purchase control

Run demo-buy.sh.
Show:
Login → 200
First purchase → 201
Second purchase → 409
“This proves one user cannot purchase the same event twice.”

5. Account lockout

Run demo-lockout.sh.
Show the five failed attempts.
Show the account becomes locked.
Try the correct password.
Show 423.
“The lockout is enforced through Redis and applies across the application instances.”

6. CI/CD

Open GitHub Actions.
Show terraform-plan.yml.
Show All checks passed.
Show PR / branch protection.
Show apply workflow if needed.
“Changes go through pull requests and automated checks before reaching main.”

7. Security

“EC2 instances are private.”
“There is no SSH access; administration uses SSM.”
“HTTPS is enforced.”
“Secrets are stored in Secrets Manager.”
“WAF provides another layer of protection.”
“Checkov passed all configured checks.”

8. Operations / cost

Show CloudWatch dashboard or screenshots.
Mention three healthy instances.
Mention alarms/drift detection.
“The projected steady-state cost is about $130.86 per month.”
“The target budget is $150.”

9. Close

“The final system is a working multi-AZ AWS application with Terraform, CI/CD, security controls, and operational checks.”
“The main lesson was that a successful Terraform plan is not enough. Real deployment and failure testing exposed issues that had to be fixed.”


WHY I CHOSE EACH PART

postgreSQL: relational db, can enforce one ticket/one person rule with a unique constraint (not just depends on the app code)
db.t4g.micro: small workload(project and not live production) COST decision mainly
OIDC: no permanent access keys(github actions proves who it is) -> AWS STS gives temporary credentials (restricted to what pipeline needs)
4 separate terraform state (foundation data-tier compute observability)
Smaller, easier-to-understand plans.
Lower blast radius if something goes wrong.
Cleaner ownership of resources.
Faster targeted Terraform operations.
Easier lifecycle management, especially because your billable resources can be toggled by layer.

The trade-off is more complexity: you have four Terraform roots to manage and they have dependencies/order between them.
