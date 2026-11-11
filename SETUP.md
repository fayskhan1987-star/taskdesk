# A&T TaskDesk: going live on task.globalaeontrisl.com

What is in this folder

| File | What it is |
|---|---|
| `index.html` | The whole app |
| `config.js` | Two settings you fill in (step 6) |
| `logo.png` | Your logo, used on the sign-in page |
| `CNAME` | Tells GitHub Pages the address is task.globalaeontrisl.com |
| `supabase/schema.sql` | The database: tables, roles, departments and security rules |
| `supabase/functions/ai/index.ts` | Optional AI helper for the Assistant, Agents and summaries (Part E) |

To look around before connecting anything, open `index.html` in a browser and press "Look around with demo data".

## Part A: Supabase (database and sign-in)

1. Go to supabase.com, create a free account and a new project (any name, region close to the UAE). Save the database password it asks you to set.
2. Open **SQL Editor**, choose New query, paste the whole of `supabase/schema.sql`, and press Run. It should finish with "Success".
3. Open **Authentication > Hooks**. Add the **Before User Created** hook, type Postgres function, schema `public`, function `hook_before_user_created`. Save. This is what refuses anyone who is not on your access list.
4. Open **Authentication > Emails (templates)**. In both the **Confirm signup** and **Magic Link** templates, replace the body with something like:
   `Your TaskDesk code is {{ .Token }}` 
   The `{{ .Token }}` part is what puts the 6-digit code in the email. Keep the code length at 6 (Authentication > Sign In / Providers > Email).
5. Open **Authentication > SMTP settings** and switch on custom SMTP so the codes come from your own Zoho mailbox:
   - Host `smtp.zoho.com`, port `465`
   - Username: the full mailbox address, for example `taskdesk@aeontrisl.com`
   - Password: an app-specific password created in Zoho Mail (Zoho account > Security > App passwords)
   - Sender email: the same mailbox; sender name: `A&T TaskDesk`
   Without this, Supabase's built-in sender only allows a few emails an hour and is meant for testing.
   Also set **Authentication > URL Configuration > Site URL** to `https://task.globalaeontrisl.com`.
6. Open **Project Settings > API**. Copy the **Project URL** and the **anon / publishable** key into `config.js`. Never use the `service_role` / secret key.

## Part B: GitHub (hosting)

7. On github.com create a new **public** repository, for example `taskdesk`. (GitHub's free plan only hosts public repositories as websites. The code and the key in `config.js` are safe to be public; your data is protected by the database rules.)
8. Upload everything in this folder to the repository (Add file > Upload files), keeping `supabase/schema.sql` if you like; it is not needed by the website.
9. In the repository open **Settings > Pages**. Under Build and deployment choose **Deploy from a branch**, branch `main`, folder `/ (root)`. Save.
10. In the same page set **Custom domain** to `task.globalaeontrisl.com` and save.

## Part C: your domain

11. Log in where the DNS for `globalaeontrisl.com` is managed and add one record:
    - Type `CNAME`, name/host `task`, value `YOUR-GITHUB-USERNAME.github.io`
12. Wait until GitHub's Pages settings show the domain as verified (minutes to a few hours), then tick **Enforce HTTPS**.

## Part D: first use

13. Open `https://task.globalaeontrisl.com`, enter your own @aeontrisl.com address and the code from your inbox. The first person to sign in becomes the Admin.
14. Go to **Team > Access** and add each person: their @aeontrisl.com email, name, department and role. They can then sign in with a code. Removing someone there locks them out straight away.

## Part E: AI features (optional)

The Assistant, Agents, meeting summaries and "Create doc with AI" need an AI service. Everything else works without this step.

15. Get an API key from console.anthropic.com (this is billed by usage, separately from any Claude subscription).
16. In Supabase open **Edge Functions**, create a function named exactly `ai`, and paste in the contents of `supabase/functions/ai/index.ts`. Deploy it.
17. In **Edge Functions > Secrets** add `ANTHROPIC_API_KEY` with your key. Optionally add `AI_MODEL` to choose a different model.

## What is not automatic on this site

- **Social publishing**: posts are written once and queued for every branch, then posted by hand from the queue (the queue opens each account for you). Posting automatically needs each platform's own approval for your accounts.
- **WhatsApp and email**: the WhatsApp and Email links open with the message ready to send from your own number or mailbox. Nothing is sent automatically.
- **Scheduled assistant prompts** run only while someone has the desk open.

## Roles

| Role | What they can do |
|---|---|
| Admin | Everything, plus the access list |
| Higher Management | Every department, the company dashboard, all sections; can assign tasks to anyone |
| Department Manager | Their own department's boards and tasks; assign to their team; send requests to other departments and accept or decline requests sent to theirs; workflows, templates, docs, apps |
| Team Member | Only their own tasks; My work, Today, chat, team directory, docs, assistant |
| Social media (a tick box on any person) | Adds the Social media section for that person |
