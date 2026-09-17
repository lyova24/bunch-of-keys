const feedbackTimers = new WeakMap();

export async function copyFieldValue({
  target,
  copy,
  onSuccess,
  onError,
  feedbackDuration = 1400,
  schedule = setTimeout,
  cancel = clearTimeout,
}) {
  try {
    await copy();
  } catch (error) {
    onError(error);
    return false;
  }

  const previousTimer = feedbackTimers.get(target);
  if (previousTimer !== undefined) cancel(previousTimer);

  target.classList.add('copied');
  const timer = schedule(() => {
    target.classList.remove('copied');
    feedbackTimers.delete(target);
  }, feedbackDuration);
  feedbackTimers.set(target, timer);
  onSuccess();
  return true;
}
