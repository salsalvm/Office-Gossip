// Push copy for social activity. Titles stay short enough for a lock screen (~50 chars); bodies carry the detail.
const NAME_MAX = 28;
const EXCERPT_MAX = 90;

export type PushContent = { title: string; body: string };

const clip = (text: string, max: number) => {
  const clean = text.replace(/\s+/g, ' ').trim();
  return clean.length > max ? `${clean.slice(0, max - 1).trimEnd()}…` : clean;
};
const displayName = (name: string | null | undefined) => clip(name || '', NAME_MAX) || 'A coworker';

export function followContent(input: { actorName?: string | null; actorRole?: string | null; followsBack: boolean }): PushContent {
  const name = displayName(input.actorName);
  if (input.followsBack) {
    return { title: `🎉 ${name} followed you back`, body: 'You’re now following each other. Say hi in your community!' };
  }
  const role = clip(input.actorRole || '', 40);
  return {
    title: `👋 ${name} started following you`,
    body: role ? `${role} · Tap to see their profile and follow back.` : 'Tap to see who it is and follow back.',
  };
}

const REACTION_COPY = {
  love: { emoji: '❤️', verb: 'loved' },
  laugh: { emoji: '😂', verb: 'laughed at' },
  fire: { emoji: '🔥', verb: 'is fired up about' },
  clap: { emoji: '👏', verb: 'applauded' },
  wow: { emoji: '😮', verb: 'was wowed by' },
} as const;

export function reactionContent(input: { reaction: keyof typeof REACTION_COPY; actorName?: string | null; othersCount: number; postBody: string; anonymousPost: boolean; hasPoll: boolean }): PushContent {
  const name = displayName(input.actorName);
  const copy = REACTION_COPY[input.reaction];
  const what = `${input.anonymousPost ? 'anonymous ' : ''}${input.hasPoll ? 'poll' : 'post'}`;
  const excerpt = clip(input.postBody, EXCERPT_MAX);
  const title = input.othersCount > 0
    ? `${copy.emoji} ${name} and ${input.othersCount} ${input.othersCount === 1 ? 'other' : 'others'} reacted to your ${what}`
    : `${copy.emoji} ${name} ${copy.verb} your ${what}`;
  return { title, body: excerpt ? `“${excerpt}”` : `Your ${what} is getting some love.` };
}
