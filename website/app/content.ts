// Every word on the page lives here, so Spanish can follow as a second object of the same shape.

export const en = {
  lang: "en",
  // The App Store page. While `url` is empty the app is not in a store yet: the button is plain
  // words, not a link. When it is, put the address here and set the label to "Download on the App Store".
  download: { label: "Download on the App Store", url: "https://apps.apple.com/app/id6836352663" },
  meta: {
    title: "Upon Thy Head",
    description:
      "Record a priesthood blessing and keep its words, for yourself and for your children. Everything stays on your phone. Free, on iPhone and iPad, and coming soon to Android.",
  },
  hero: {
    name: "Upon Thy Head",
    sentence: "Record a priesthood blessing and keep its words, for yourself and for your children. Everything stays on your phone.",
    note: "Free. No ads. No account.",
  },
  // The held scene under the name: the arc of lights draws away into a halo that turns.
  journey: {
    one: "Keep every blessing you are given.",
    two: "Keep your children’s until they are grown.",
  },
  sky: {
    heading: "Every blessing, where you can find it",
    body: [
      "Home is a night sky with one light for each blessing, in the order they were given. Touch a light and the blessing opens to read.",
      "Looking for one from years ago? Slide along the dates at the bottom, or open the list.",
    ],
  },
  family: {
    heading: "For you, and for your children",
    body: [
      "Add each of your children and keep their blessings beside your own. A father’s blessing before a new school year goes on that child’s own sky, not yours.",
      "When they are grown, hand it all over. One link, and every blessing you kept for them is on their own phone.",
    ],
  },
  steps: {
    heading: "How it works",
    items: [
      {
        shot: "recording",
        title: "Record the blessing",
        body: "Set the phone nearby and press Begin. It listens while the blessing is given, and keeps listening with the screen locked.",
      },
      {
        shot: "changes",
        title: "The phone writes the words",
        body: "The writing is done on the phone itself. Nothing is sent anywhere to be written down.",
      },
      {
        shot: "reading",
        title: "Read it and keep it",
        body: "Read the words through and correct anything misheard. Then the recording is erased and the writing stays.",
      },
    ],
  },
  // The demonstration. Plain strings are kept as spoken; { cut } marks a word the tidy-up leaves out.
  words: {
    heading: "Word for word",
    body: "Nothing is summarised or reworded. If you ask, the app leaves out an “um” or a word said twice, shows you every change, and lets you undo each one.",
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
  past: {
    heading: "Blessings you already have",
    body: [
      "Have a blessing typed up years ago, or written in a journal? Type it or paste it in, with the date it was given.",
      "If you only remember the year, that is enough. It takes its place among the others.",
    ],
  },
  promises: {
    heading: "Private, and yours",
    items: [
      {
        title: "Everything stays on your phone.",
        body: "The recording is written down on the phone itself. There is no account, and no copy of your blessings on our servers.",
      },
      {
        title: "The recording is erased.",
        body: "Once you have read the words through, the recording is erased. The writing stays.",
      },
      {
        title: "Your blessings are locked.",
        body: "They open with Face ID, or with your fingerprint or screen lock.",
      },
      {
        title: "Shared only when you choose.",
        body: "If you send a blessing as a link, a locked copy is kept for 30 days so the other person can open it. The key is in the link itself, so we cannot read it.",
      },
      {
        title: "Free.",
        body: "No ads and no account. In English and Spanish, on iPhone, iPad and Android.",
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
          { label: "Help", href: "/support" },
          { label: "Privacy", href: "/privacy" },
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
  // The privacy page. Every sentence here is a promise the app and the link service must keep:
  // change the code and this page together.
  privacy: {
    title: "Privacy",
    description: "What the app Upon Thy Head and uponthyhead.app know about you: nothing. Your blessings stay on your phone.",
    changed: "Last changed 20 November 2026.",
    intro:
      "This is the privacy policy for the app Upon Thy Head and for this website. In short: your blessings stay on your phone, there is no account, and we collect nothing about you.",
    back: "Upon Thy Head",
    sections: [
      {
        heading: "What stays on your phone",
        body: [
          [
            "Everything you put in the app is kept in the app’s own storage on your phone or tablet: the words of each blessing, its date, who gave it, the names of your family members, and your settings. None of it is sent to us. We have no copy and no way to read it.",
          ],
          [
            "A recording is kept only until you have read the words through. Then it is erased. Recordings are left out of iCloud and computer backups.",
          ],
          [
            "If you back up your iPhone or iPad with iCloud or a computer, the written blessings are part of that backup, as with any app. That backup is between you and Apple. On Android the app’s data is not included in Google’s backup.",
          ],
        ],
      },
      {
        heading: "What the app asks your phone for",
        body: [
          [
            "The microphone, only while you are recording a blessing. The sound is written down by the phone itself. It is not sent to us, to Apple, to Google or to anyone else. On Android the app downloads a speech model once, the first time it is needed; after that the writing needs no connection.",
          ],
          [
            "Your location, once, if you allow it, and only roughly. It is used to set the sky to the place where your first blessing was given. It is kept on the phone and never sent anywhere. The app works without it.",
          ],
          [
            "Face ID, your fingerprint or your screen lock, to open the app. The phone does the checking and tells the app only yes or no.",
          ],
        ],
      },
      {
        heading: "When you share a blessing as a link",
        body: [
          [
            "This is the only time anything leaves your phone for our servers, and it happens only when you choose it. The phone locks a copy of the blessing and sends the locked copy to this site, which keeps it for 30 days so the other person can open it. The key is the part of the link after the #. It never reaches us, so we cannot read the copy.",
          ],
          [
            "With the locked copy we keep the day it stops and a value that lets your phone stop it early. We keep nothing about you, your phone or the person you send it to. You can stop a link from the app at any time, and the copy is removed at once.",
          ],
          [
            "Sharing a blessing as a file, as text or as a PDF does not involve us at all. It goes wherever you send it.",
          ],
        ],
      },
      {
        heading: "Keeping the link service from being misused",
        body: [
          [
            "To stop one sender from overloading the service, it counts requests from each internet address for a short time. The address is mixed with a secret and only the mix is held, in memory. It is never stored and never written to a log of ours.",
          ],
          [
            "The app can also prove to the service that it is a real copy of Upon Thy Head, using Apple’s App Attest or Google’s Play Integrity. This tells us only that the app is real. Nothing about your phone is kept.",
          ],
        ],
      },
      {
        heading: "This website",
        body: [
          [
            "This site has no analytics, no advertising, no tracking and no cookies. It is hosted by Vercel, and locked copies of shared blessings are stored with Neon. As with any website, the hosting company’s systems see your internet address in order to send you the page, and may keep technical logs for a short time. We do not use them to learn who you are.",
          ],
        ],
      },
      {
        heading: "What we do not do",
        body: [
          [
            "There is no account and nothing to sign in to. There are no ads. Nothing in the app tracks you or measures how you use it. We do not sell or pass on information about you, because we have none.",
          ],
        ],
      },
      {
        heading: "Children",
        body: [
          [
            "A parent can keep a child’s blessings in the app on the parent’s own phone. The app collects nothing from anyone, children included.",
          ],
        ],
      },
      {
        heading: "Removing what you have kept",
        body: [
          [
            "Delete a blessing in the app and it is gone from the phone. Remove the app and everything it kept is removed with it. A shared link stops when you stop it, or by itself after 30 days, and the locked copy is then removed from our servers.",
          ],
        ],
      },
      {
        heading: "Changes and questions",
        body: [
          [
            "If this policy changes, the new one will be on this page with a new date. Questions go to ",
            { link: "hello@summitstudio.dev", href: "mailto:hello@summitstudio.dev" },
            " or to ",
            { link: "Summit Studio", href: "https://www.summitstudio.dev/contact" },
            ".",
          ],
        ],
      },
    ],
  },
  // The help page: where to write, and the questions people are likely to have.
  support: {
    title: "Help",
    description: "Help with the app Upon Thy Head, and how to reach Summit Studio.",
    changed: "",
    intro:
      "Upon Thy Head is made by Summit Studio. If something is not working, or you have a question that is not answered here, write to us and a person will answer.",
    back: "Upon Thy Head",
    sections: [
      {
        heading: "Write to us",
        body: [
          [
            { link: "hello@summitstudio.dev", href: "mailto:hello@summitstudio.dev" },
            ". It helps to say which phone or tablet you have. Please do not send us the words of a blessing; we never need them to help you.",
          ],
        ],
      },
      {
        heading: "The app will not record",
        body: [
          [
            "The app needs the microphone and, on iPhone and iPad, speech recognition. If you answered “Don’t Allow” the first time, open the Settings app, find Upon Thy Head, and turn on Microphone and Speech Recognition.",
          ],
          [
            "Set the phone near the person giving the blessing, face up, and press Begin. It keeps listening with the screen locked.",
          ],
        ],
      },
      {
        heading: "Some words were written wrongly",
        body: [
          [
            "The writing is done by the phone and it can mishear. Before you keep a blessing, read it through and correct anything that is wrong. You can listen to the recording while you read. You can also correct the words later, from the blessing itself.",
          ],
        ],
      },
      {
        heading: "I have a blessing that is already written down",
        body: [
          [
            "Choose to enter a past blessing, then type or paste the words and give the date. If you only know the year, or the month and year, that is enough.",
          ],
        ],
      },
      {
        heading: "Keeping blessings for my children",
        body: [
          [
            "Touch “For me” at the top of the home screen and add a family member. Each one has their own sky. When a child is grown, open Manage family and hand their blessings over: the app makes one link that puts all of them on the child’s own phone.",
          ],
        ],
      },
      {
        heading: "A link I was sent will not open",
        body: [
          [
            "A link works for 30 days, or until the person who sent it stops it. After that the blessing is no longer there to open. Ask them to send it again. The whole link is needed, including everything after the #.",
          ],
        ],
      },
      {
        heading: "I lost my phone, or removed the app",
        body: [
          [
            "Your blessings are kept only on your phone, so we have no copy to give back. If you restore a new iPhone or iPad from a backup of the old one, the written blessings come back with it.",
          ],
          [
            "To keep a copy somewhere else, open a blessing, choose to share it, and save it as a file or a PDF.",
          ],
        ],
      },
      {
        heading: "More",
        body: [
          [
            "How the app treats what you keep in it is on the ",
            { link: "privacy page", href: "/privacy" },
            ". The terms are on the ",
            { link: "terms page", href: "/terms" },
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
      alt: "The app’s home screen: a night sky with one light for each blessing, the newest named at the bottom above a row of dates.",
    },
    family: {
      label: "Family",
      alt: "The menu on the home screen: For me, For Emma, Add a family member, Manage family.",
    },
    entry: {
      label: "A past blessing",
      alt: "The page for entering a past blessing: the date it was given, who gave it, and its words pasted in.",
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
