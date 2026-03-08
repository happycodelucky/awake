# Understanding Managed Policy Warnings

Awake shows a warning card when it detects that your organization has applied rules to your Mac that could interrupt your session. This guide explains what those warnings mean, why they appear, and what you can do about them.

The warnings are **informational, not errors**. Awake is letting you know what to expect so you are not caught off guard.

---

## What are managed policies?

If your Mac is provided or managed by an employer, school, or IT department, it may have a device management profile installed. These profiles — delivered through a system called MDM (Mobile Device Management) — let your organization enforce security rules across all managed devices automatically.

Some of those rules are designed to protect the device if it is left unattended: the screen saver may start after a period of inactivity, the Mac may lock or log you out after sitting idle for too long, or a password prompt may appear when you come back to a locked screen.

You may never have installed these rules yourself, and you may not even be aware they are there. They are applied quietly in the background by your organization.

---

## When does Awake show a warning?

Awake checks your device for managed policies each time it runs. If it finds policies that could interrupt a session — by triggering the screen saver, requiring a password, or logging you out — it shows an orange warning card inside the menu popover.

The warning card appears above the timer controls whenever relevant policies are detected. It lists what Awake found, so you can decide how to proceed.

---

## What policies does Awake detect?

Awake looks for three types of managed rules that can affect an active session:

### Screen saver idle timeout

Your organization may have set a rule that starts the screen saver after your Mac has been idle for a certain amount of time. For example, the screen saver might activate after 5 minutes of no keyboard or mouse activity.

Awake prevents your Mac from going to sleep, but a managed screen saver timeout can still activate on top of an active session. If your display is allowed to sleep, the screen saver may start during that sleep period.

### Auto-logout

Your Mac may be configured to automatically log you out if it has been idle for too long. This is a more aggressive policy than a screen saver: when auto-logout triggers, all your running applications and open work are closed and the Mac returns to the login screen.

Auto-logout is the most disruptive policy Awake can detect. It will end your session regardless of whether Awake is running.

### Password after screen saver

Your organization may require you to re-enter your password when you return from the screen saver. This means that if the screen saver activates, your Mac will be locked and you will need to authenticate to get back in.

This policy is often paired with the screen saver idle timeout. If both are active, an idle period will trigger the screen saver and then immediately require a password to continue.

---

## What do "Known" and "Likely" mean?

The warning card groups policies into two categories:

**Known** — These are policies that are confirmed to be active on your device and will affect your session. For example, if auto-logout is set to 30 minutes, it appears as a Known warning because it will definitely trigger after 30 minutes of idle time regardless of what Awake is doing.

**Likely** — These are policies that may affect your session depending on how you use Awake. For example, a screen saver timeout is listed as Likely if it could activate depending on your chosen sleep mode or how long your session runs. Whether it actually triggers depends on your settings and behavior.

Both categories are worth reading. Known warnings describe things that will happen. Likely warnings describe things that might happen.

---

## What can Awake do about it?

Awake prevents your Mac from going idle at the system level. This stops automatic sleep, display sleep, and the kind of inactivity that normally triggers a screen saver — as long as the session is active and the display is kept awake.

However, Awake **cannot bypass** managed lock or logout policies enforced by your organization. These rules are applied by the operating system itself and operate independently of any app. If your Mac is configured to auto-logout after a period of inactivity, that logout will still happen. Awake can warn you that it will happen, but it cannot prevent it.

Think of Awake as doing its best within the rules your organization has set. It keeps the Mac from sleeping on its own, but it cannot override policies your IT department has put in place for security reasons.

---

## What can you do?

Here are some practical steps if managed policies are getting in the way of your work:

**Keep the display awake for the strongest protection.**
Awake has two sleep modes: one that keeps the display fully on, and one that allows the display to sleep while keeping the system awake. Keeping the display on provides the strongest defense against screen saver timeouts and password-lock policies. If you are seeing screen saver or lock-screen interruptions, try switching to the mode that keeps your display awake.

**Use shorter timer presets to stay within policy windows.**
If your organization has a 30-minute auto-logout policy, running a 2-hour Awake session will still result in a logout. Instead, set a timer that ends before the policy would trigger, so you are actively at your Mac when the session completes. The shorter presets — 5, 10, 15, or 30 minutes — are useful for staying within tight policy windows.

**Contact your IT department if policies are too restrictive for your workflow.**
If managed policies are frequently interrupting legitimate work — long builds, large downloads, unattended processes — your IT department may be able to adjust the timeouts for your account or advise on approved alternatives. They are the right people to talk to, since only they can change what the policies allow.
