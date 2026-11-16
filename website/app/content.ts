// Every word on the page lives here, so Spanish can follow as a second object of the same shape.

export const en = {
  lang: "en",
  // The App Store page. Replace with the real address once the app has one.
  download: { label: "Download on the App Store", url: "https://apps.apple.com/app/upon-thy-head" },
  meta: {
    title: "Upon Thy Head",
    description:
      "A written record of the blessings given to you. The words stay on your phone. Free on iPhone.",
  },
  hero: {
    name: "Upon Thy Head",
    sentence: "A written record of the blessings given to you, kept on your own phone.",
    note: "Free. No ads. No account.",
  },
  // The held scene under the name: the arc of lights draws away into a halo that turns.
  journey: {
    one: "Each blessing is a light.",
    two: "Touch one, and the blessing opens to read.",
  },
  sky: {
    heading: "A life becomes a line of lights",
    body: [
      "The first thing you see is the night sky. Each blessing you have received is one small, warm light on a ring that crosses overhead.",
      "The lights gather over the years, each one where it was given. Touch one, and the blessing opens to read.",
    ],
  },
  steps: {
    heading: "From the blessing to the page",
    items: [
      {
        shot: "recording",
        title: "A blessing is given",
        body: "A father’s blessing, a blessing of comfort, a blessing before surgery. Someone sets a phone nearby, and it listens while the words are spoken.",
      },
      {
        shot: "changes",
        title: "The words are written",
        body: "The phone writes down what was said. It does the work itself; nothing is sent away to be written down.",
      },
      {
        shot: "reading",
        title: "They are kept",
        body: "Read the words through once. Then the recording is erased and the writing stays, yours to open again whenever you need it.",
      },
    ],
  },
  // The demonstration. Plain strings are kept as spoken; { cut } marks a word the tidy-up leaves out.
  words: {
    heading: "Word for word",
    body: "Nothing is summarised. Nothing is reworded. If you ask, the app leaves out an “um” or a word said twice. It shows you every change, and each one can be undone.",
    sample: [
      "Emma, I lay my hands upon your head,",
      { cut: "um," },
      "to give you a blessing",
      { cut: "of" },
      "of comfort. Your Heavenly Father knows you. He knows the worry you have carried these weeks, and",
      { cut: "uh," },
      "He wants you to know that you have not carried it alone.",
    ],
    leaveOut: "Leave out",
    count: "Words left out:",
    hint: "Touch a crossed-out word to put it back.",
  },
  promises: {
    heading: "What it promises",
    items: [
      {
        title: "The words stay on your phone.",
        body: "The recording is turned into writing on the phone itself, and there is no account. When you share a blessing, a locked copy is kept for 30 days so the person you sent it to can open it. We cannot read it.",
      },
      {
        title: "The recording is erased.",
        body: "Once you have reviewed the words, the recording is erased. The writing stays.",
      },
      {
        title: "Your blessings are locked.",
        body: "They open with Face ID.",
      },
      {
        title: "It is free.",
        body: "No ads. In English and Spanish.",
      },
    ],
  },
  share: {
    heading: "Yours to share",
    body: "Share a blessing as text, as a PDF, or as a file that opens in the app on another iPhone.",
    note: "Once it leaves this phone, it is no longer private to it.",
  },
  close: {
    heading: "Upon Thy Head",
    note: "Free on iPhone. No ads. No account.",
    iconLabel: "App icon",
  },
  footer: {
    notOfficial:
      "Upon Thy Head is not an official app of The Church of Jesus Christ of Latter-day Saints.",
    builtBy: "Built by",
    builder: "Summit Studio",
    builderUrl: "https://summitstudio.dev",
    credits:
      "The sky on this page is the real one: stars from the HYG Database by David Nash (CC BY-SA 4.0), and the Milky Way from the NASA/Goddard Space Flight Center Scientific Visualization Studio. The typeface is Newsreader by Production Type (SIL Open Font License 1.1).",
  },
  // The pictures of the app. `label` is shown until the picture exists; `alt` describes it after.
  shots: {
    sky: {
      label: "The sky",
      alt: "The app’s home screen: the night sky, with one warm light for each blessing on a ring overhead.",
    },
    recording: {
      label: "Recording",
      alt: "The app listening while a blessing is spoken.",
    },
    changes: {
      label: "The changes",
      alt: "The list of small changes made to the words, each of which can be undone.",
    },
    reading: {
      label: "Reading a blessing",
      alt: "A blessing open to read, with its date and who gave it.",
    },
    sharing: {
      label: "Sharing",
      alt: "The choices for sharing a blessing: text, PDF, or a file for another iPhone.",
    },
  },
} as const;

export type Content = typeof en;
export type ShotName = keyof Content["shots"];
