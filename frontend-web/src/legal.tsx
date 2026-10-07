import React from 'react';

export const SUPPORT_EMAIL = import.meta.env.VITE_SUPPORT_EMAIL || 'support@officegossip.app';
const UPDATED = 'October 6, 2026';

type Section = { group?: string; heading: string; body: React.ReactNode };
type LegalDoc = { short: string; eyebrow: string; title: string; intro: React.ReactNode; sections: Section[] };

const mail = <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>;

const DOCS: Record<string, LegalDoc> = {
  privacy: {
    short: 'Privacy',
    eyebrow: 'PRIVACY POLICY',
    title: 'How we handle your data',
    intro: <>Office Gossip is a workplace community. This policy explains what we collect, why we collect it, and the choices you have. Questions? Email {mail}.</>,
    sections: [
      { heading: 'What we collect', body: <ul><li><b>Account details</b> — your email address, phone number (if you sign in with it), and sign-in provider such as Google.</li><li><b>Profile details</b> — display name, role, bio, theme preference, and the company you belong to or request to join.</li><li><b>Content</b> — posts, comments, reactions, and reports you submit.</li><li><b>Device details</b> — push notification tokens if you turn on notifications.</li><li><b>Basic technical data</b> — logs needed to keep the service secure and working.</li></ul> },
      { heading: 'Anonymous posts', body: <p>When you post anonymously, other members do not see your name or role. We still store which account created the post so we can enforce our terms, respond to reports, and comply with the law. Company admins do not see the author of anonymous posts.</p> },
      { heading: 'How we use it', body: <><ul><li>To run your account, show your company and global community feeds, and deliver notifications you have enabled.</li><li>To verify company membership and review company requests.</li><li>To keep the community safe, including reviewing reports and preventing abuse.</li><li>To improve the product and fix problems.</li></ul><p>We do not sell your personal data, and we do not use it for third-party advertising.</p></> },
      { heading: 'Who we share it with', body: <p>We use trusted providers to run the service: Supabase for authentication and database hosting, Google for sign-in, and Firebase Cloud Messaging for push notifications. They process data only to provide these services to us. We may also disclose information if required by law or to protect members’ safety.</p> },
      { heading: 'How long we keep it', body: <p>We keep your data while your account is active. Deleted posts are removed from the feed immediately. If you ask us to delete your account, we delete or anonymise your personal data within 30 days, except where we must keep it for legal reasons.</p> },
      { heading: 'Your choices and rights', body: <p>You can edit your profile and notification preferences from your profile page at any time. You can also ask us to access, correct, export, or delete your data by emailing {mail}.</p> },
      { heading: 'Security', body: <p>Data is encrypted in transit and access is restricted to the people and systems that need it. No service is perfectly secure, so please use a strong, unique password.</p> },
      { heading: 'Children', body: <p>Office Gossip is for working adults and is not intended for anyone under 18.</p> },
      { heading: 'Changes', body: <p>If we make significant changes to this policy we will let you know in the app before they take effect.</p> },
    ],
  },
  terms: {
    short: 'Terms',
    eyebrow: 'TERMS & CONDITIONS',
    title: 'Rules for using Office Gossip',
    intro: <>By creating an account or using Office Gossip you agree to these terms. If you do not agree, please do not use the service.</>,
    sections: [
      { heading: 'Your account', body: <ul><li>You must be at least 18 and provide accurate information.</li><li>Keep your sign-in details secure. You are responsible for activity on your account.</li><li>Only join a company community you genuinely belong to. A matching email domain alone does not prove employment.</li></ul> },
      { heading: 'Community guidelines', body: <><p>Office Gossip is meant to be a kinder corner of the internet. Do not post content that:</p><ul><li>harasses, bullies, threatens, or discriminates against anyone;</li><li>shares someone’s private or personal information without consent;</li><li>reveals confidential company information or trade secrets;</li><li>is defamatory, sexually explicit, violent, or illegal;</li><li>is spam, impersonation, or misleading.</li></ul><p>Posting anonymously does not exempt you from these rules.</p></> },
      { heading: 'Your content', body: <p>You own what you post. You give us permission to store, display, and distribute it within Office Gossip so the service can work. You are responsible for what you post and for having the right to share it.</p> },
      { heading: 'Moderation', body: <p>Members can report posts. We may review, hide, or remove content and suspend or close accounts that break these terms, with or without notice.</p> },
      { heading: 'Company communities', body: <p>Company communities are run by Office Gossip, not by your employer. Your employer does not control your account, and anything you post is not an official statement from your company.</p> },
      { heading: 'Service availability', body: <p>We work to keep Office Gossip available but provide it “as is”, without warranties. We may change, pause, or discontinue features at any time.</p> },
      { heading: 'Limitation of liability', body: <p>To the extent allowed by law, Office Gossip is not liable for indirect or consequential losses, or for content posted by other members.</p> },
      { heading: 'Ending your account', body: <p>You can stop using Office Gossip at any time and ask us to delete your account by emailing {mail}.</p> },
      { heading: 'Changes', body: <p>We may update these terms. If changes are significant we will notify you in the app. Continuing to use Office Gossip after that means you accept the updated terms.</p> },
    ],
  },
  contact: {
    short: 'Help & contact',
    eyebrow: 'HELP & CONTACT',
    title: 'How can we help?',
    intro: <>Find quick answers below, or reach out and a real person will get back to you, usually within two business days.</>,
    sections: [
      { group: 'Get in touch', heading: 'Support and general questions', body: <p>Email {mail}. Include the email address on your account so we can find it quickly.</p> },
      { heading: 'Report a post or a safety concern', body: <p>Use <b>Report</b> from the ··· menu on any post — reports are anonymous. For urgent safety concerns, email {mail} with “Urgent” in the subject.</p> },
      { heading: 'Privacy and data requests', body: <p>To access, export, correct, or delete your data, email {mail} with the subject “Privacy request”.</p> },
      { group: 'Frequently asked questions', heading: 'Why can’t I post yet?', body: <p>You need a display name and an approved company membership. If you requested a new company, you can post once an admin approves it.</p> },
      { heading: 'How do I add my company?', body: <p>Choose “Request a new company” when you sign up. Our team reviews every request.</p> },
      { heading: 'Who can see my anonymous posts?', body: <p>Other members see the post without your name or role. See the <a href="/privacy">Privacy policy</a> for details.</p> },
      { heading: 'What is the difference between Global and company communities?', body: <p>Your company community shows posts from coworkers. The Global community shows posts from everyone on Office Gossip.</p> },
      { heading: 'How do I change notifications?', body: <p>Open your profile and use the Notifications setting. You can also enable push notifications there.</p> },
      { heading: 'I forgot my password', body: <p>On the sign-in screen choose “Forgot password?” and we will email you a reset link.</p> },
      { heading: 'How do I delete my account?', body: <p>Email {mail} from the address on your account and we will take care of it.</p> },
    ],
  },
};

export const LEGAL_PATHS = Object.keys(DOCS);
// Older links (including the mobile app) still open /help.
export const LEGAL_ALIASES: Record<string, string> = { help: 'contact' };

export function LegalPage({ path }: { path: string }) {
  const doc = DOCS[path];
  const embedded = window.self !== window.top;
  return <div className="legal-page">
    {!embedded && <header className="legal-top"><a className="legal-brand" href="/"><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><span>office<span>gossip</span></span></a><nav>{LEGAL_PATHS.map(p => <a key={p} href={`/${p}`} className={p === path ? 'active' : ''}>{DOCS[p].short}</a>)}</nav></header>}
    <main className="legal-body">
      <span className="overline">{doc.eyebrow}</span>
      <h1>{doc.title}</h1>
      <p className="legal-intro">{doc.intro}</p>
      {path !== 'contact' && <small className="legal-updated">Last updated {UPDATED}</small>}
      {doc.sections.map(section => <React.Fragment key={section.heading}>{section.group && <h3 className="legal-group">{section.group}</h3>}<section><h2>{section.heading}</h2>{section.body}</section></React.Fragment>)}
    </main>
    {!embedded && <footer className="legal-foot">Office Gossip · A kinder corner of the internet</footer>}
  </div>;
}
