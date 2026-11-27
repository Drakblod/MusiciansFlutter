'use strict';

const millisecondsPerHour = 3_600_000;

// BandEvent.fromJson also accepts integer strings in older records.
function rsvpInteger(value) {
  if (typeof value === 'string') {
    const clean = value.trim();
    if (!/^[+-]?(?:\d+|0x[\da-f]+)$/i.test(clean)) return null;
    value = Number.parseInt(clean);
  }
  return Number.isSafeInteger(value) ? value : null;
}

// Match RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs in Flutter.
function effectiveRsvpDeadlineMs(event) {
  if (event.requireResponse !== true) return null;
  const interval = rsvpInteger(event.reminderIntervalHours);
  if (interval === 0) return null;

  const createdAt = rsvpInteger(event.createdAt);
  if (createdAt > 0 && interval > 0) {
    const deadline = createdAt + interval * millisecondsPerHour;
    if (Number.isSafeInteger(deadline)) return deadline;
  }

  const stored = rsvpInteger(event.rsvpDeadline);
  return stored > 0 ? stored : null;
}

function isBeforeRsvpDeadline(deadlineMs, nowMs = Date.now()) {
  return deadlineMs == null || nowMs < deadlineMs;
}

module.exports = { effectiveRsvpDeadlineMs, isBeforeRsvpDeadline, rsvpInteger };
