const graphqlRequest = async (baseUrl, graphql) => {
  const myHeaders = new Headers();
  myHeaders.append("Content-Type", "application/json");

  const requestOptions = {
    method: "POST",
    headers: myHeaders,
    // mode: "cors", // no-cors, *cors, same-origin
    // cache: "no-cache", // *default, no-cache, reload, force-cache, only-if-cached
    // credentials: "same-origin", // include, *same-origin, omit
    body: JSON.stringify(graphql),
    redirect: "follow",
  };

  return fetch(`${baseUrl}/naive_api`, requestOptions)
    .catch((error) => console.error(error))
    .then((response) => response.json());
};

const EcoTaxi = {
  generateUserKeypair: () => enigma.generate_keypair(),
  packUserStorage: (name, keypair, rooms = [], contacts = {}) => {
    const combinedKeypair = (keypair) => {
      const combined = new Uint8Array(32 + 33);
      combined.set(Buffer.from(keypair.private, "base64"), 0);
      combined.set(Buffer.from(keypair.public, "base64"), 32);
      return Buffer.from(combined).toString("base64");
    };
    return [[name, combinedKeypair(keypair)], rooms, contacts];
  },
  buildUserLink: (keypair, baseUrl) => {
    const generateUserLinkPath = (keypair) =>
      `/chat/${Buffer.from(keypair.public, "base64").toString("hex")}`;

    const generateUserLink = (baseLink, keypair) =>
      `${baseLink}${generateUserLinkPath(keypair)}`;

    return generateUserLink(baseUrl, keypair);
  },
  registerUser: async (name, keypair, baseUrl) => {
    const signUser = (name, keypair, baseUrl) =>
      graphqlRequest(baseUrl, {
        query:
          "mutation SignUp($name: String!, $keypair: InputKeyPair) {\n  userSignUp(name: $name, keypair: $keypair) {\n    name\n    keys {\n      private_key\n      public_key\n    }\n  }\n}",
        variables: {
          name: name,
          keypair: {
            publicKey: Buffer.from(keypair.public, "base64").toString("hex"),
            privateKey: Buffer.from(keypair.private, "base64").toString(
              "hex",
            ),
          },
        },
      });

    return await signUser(
      name,
      keypair,
      baseUrl
    );
  },
  sendMessage: async (baseUrl, myKeyPair, peerPublicKey_hex, text) => {
    const timestamp = Math.floor(Date.now() / 1000);

    const response = graphqlRequest(baseUrl, {
      query: `
        mutation ($keypair: InputKeyPair!, $peer: PublicKey!, $text: String!, $timestamp: Int!) {
          chatSendText(myKeypair: $keypair, peerPublicKey: $peer, text: $text, timestamp: $timestamp) {
            id
            index
          }
        }
      `,
      variables: {
        keypair: {
          publicKey: Buffer.from(myKeyPair.public, "base64").toString("hex"),
          privateKey: Buffer.from(myKeyPair.private, "base64").toString("hex"),
        },
        peer: peerPublicKey_hex,
        text: text,
        timestamp: timestamp
      }
    });
    return await response;
  },
  getMessages: async (baseUrl, myKeyPair, peerPublicKey_hex, amount, beforeIndex) => {
    const response = await graphqlRequest(baseUrl, {
      query: `
        query ($keypair: InputKeyPair!, $peer: PublicKey!, $lastIndex: Int, $amount: Int!) {
          chatRead(myKeypair: $keypair, peerPublicKey: $peer, amount: $amount, before: $lastIndex) {
            id
            index
            timestamp
            author {
              publicKey
              name
            }
            content {
              __typename
              ... on FileContent {
                url
                type
                sizeBytes
                initialName
              }
              ... on TextContent {
               text
              }
            }
          }
        }
      `,
      variables: {
        keypair: {
          publicKey: Buffer.from(myKeyPair.public, "base64").toString("hex"),
          privateKey: Buffer.from(myKeyPair.private, "base64").toString("hex"),
        },
        peer: peerPublicKey_hex,
        amount: amount,
        lastIndex: beforeIndex
      }
    });

    return response?.data?.chatRead;
  },
  saveToStorage: (user, data) => {
    localStorage.setItem("user", JSON.stringify(user));
    localStorage.setItem("data", JSON.stringify(data));
  },
  isDataStored: () => {
    return !!localStorage.getItem("user") && !!localStorage.getItem("data");
  },
  getData: () => {
    return {
      user: JSON.parse(localStorage.getItem("user")),
      data: JSON.parse(localStorage.getItem("data")),
    };
  },
};

window.EcoTaxi = EcoTaxi;
