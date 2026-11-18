// Every word on the page lives here, so Spanish can follow as a second object of the same shape.

export const en = {
  lang: "en",
  // The App Store page. While `url` is empty the app is not in a store yet: the button is plain
  // words, not a link. When it is, put the address here and set the label to "Download on the App Store".
  download: { label: "Coming soon to iPhone and Android", url: "" },
  meta: {
    title: "Upon Thy Head",
    description:
      "A written record of the blessings given to you. The words stay on your phone. Free, and coming soon to iPhone and Android.",
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
        body: "They open with Face ID, or with your fingerprint or screen lock.",
      },
      {
        title: "It is free.",
        body: "No ads. In English and Spanish.",
      },
    ],
  },
  share: {
    heading: "Yours to share",
    body: "Send a blessing as a link that opens in the app on another phone, or share only the words as text or a PDF.",
    note: "Once it leaves this phone, it is no longer private to it.",
  },
  close: {
    heading: "Upon Thy Head",
    note: "Free. No ads. No account.",
    iconLabel: "App icon",
  },
  // The footer is Summit Studio's own: its logo, colours and layout, as on summitstudio.dev.
  footer: {
    builder: "Summit Studio",
    builderUrl: "https://www.summitstudio.dev",
    about: "Upon Thy Head is built by Summit Studio, a software studio in Cookeville, Tennessee.",
    emailLabel: "Get in touch",
    email: "hello@summitstudio.dev",
    columns: [
      {
        heading: "Upon Thy Head",
        links: [
          { label: "Home", href: "/" },
          { label: "Terms", href: "/terms" },
        ],
      },
    ],
    notOfficial:
      "Upon Thy Head is not an official app of The Church of Jesus Christ of Latter-day Saints.",
    credits:
      "The sky on this site is the real one: stars from the HYG Database by David Nash (CC BY-SA 4.0), and the Milky Way from the NASA/Goddard Space Flight Center Scientific Visualization Studio. The typeface is Newsreader by Production Type (SIL Open Font License 1.1).",
    rights: "© 2026 Summit Studio, LLC. All rights reserved.",
  },
  // The terms page. A paragraph is a list of parts: plain words, or { link, href } for a link.
  terms: {
    title: "Terms",
    description: "The terms for the app Upon Thy Head and for uponthyhead.app.",
    changed: "Last changed 18 November 2026.",
    intro:
      "These are the terms for the app Upon Thy Head and for this website. By using either one, you agree to them.",
    back: "Upon Thy Head",
    sections: [
      {
        heading: "What the app does",
        body: [
          [
            "Upon Thy Head listens while a blessing is spoken and writes the words down on your phone. It is free, it has no ads, and it needs no account.",
          ],
          [
            "The writing is done by the phone and it can be wrong. Read the words through before the recording is erased, and correct what was misheard.",
          ],
        ],
      },
      {
        heading: "Recording a blessing",
        body: [
          [
            "The Church of Jesus Christ of Latter-day Saints has its own policy on which blessings may be recorded and written down. It is in the General Handbook, section 38.2.2, ",
            {
              link: "Photographs, Recordings, and Transcriptions of Ordinances and Blessings",
              href: "https://www.churchofjesuschrist.org/study/manual/general-handbook/38-church-policies-and-guidelines?lang=eng&id=title_number19#title_number19",
            },
            " (",
            {
              link: "en español",
              href: "https://www.churchofjesuschrist.org/study/manual/general-handbook/38-church-policies-and-guidelines?lang=spa&id=title_number19#title_number19",
              lang: "es",
            },
            "), and in section 18.14.1 on ",
            {
              link: "father’s blessings",
              href: "https://www.churchofjesuschrist.org/study/manual/general-handbook/18-priesthood-ordinances-and-blessings?lang=eng&id=title_number46#title_number46",
            },
            ". Please read it.",
          ],
          [
            "The app does not know what kind of blessing is being given and does not decide for you. Whether to record a blessing is your choice, and so is following the Church’s policy.",
          ],
          [
            "Ask the person giving the blessing, and anyone else whose voice will be heard, before you record. In some places the law requires it.",
          ],
        ],
      },
      {
        heading: "Your blessings are yours",
        body: [
          [
            "The words stay on your phone. We do not receive them and we cannot read them. Keeping them safe, and keeping a copy if you want one, is up to you: if the phone is lost or the app is removed, we cannot bring them back.",
          ],
        ],
      },
      {
        heading: "Sharing a blessing",
        body: [
          [
            "When you share a blessing as a link, the phone locks a copy and this site keeps the locked copy for 30 days. The key is in the link itself and never reaches us, so we cannot read the copy.",
          ],
          [
            "Anyone who has the whole link can read the blessing until the link stops. You can stop it from the app at any time. Share only blessings that are yours to share.",
          ],
          ["Do not use the link service to send anything that is not a blessing, or to overload it."],
        ],
      },
      {
        heading: "Not an official app",
        body: [
          [
            "Upon Thy Head is made by Summit Studio. It is not made, approved or supported by The Church of Jesus Christ of Latter-day Saints.",
          ],
        ],
      },
      {
        heading: "No promises beyond these",
        body: [
          [
            "The app and this site are offered as they are, free of charge, with no warranty. As far as the law allows, Summit Studio is not responsible for loss that comes from using them, including words written wrongly or blessings that are lost.",
          ],
        ],
      },
      {
        heading: "Changes and questions",
        body: [
          [
            "If these terms change, the new ones will be on this page with a new date. Questions go to ",
            { link: "Summit Studio", href: "https://www.summitstudio.dev/contact" },
            ".",
          ],
        ],
      },
    ],
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
      alt: "The choices for sharing a blessing: a link, or only the words as text or a PDF.",
    },
  },
} as const;

export type Content = typeof en;
export type ShotName = keyof Content["shots"];
