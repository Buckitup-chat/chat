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
    const signUser = (name, keypair, baseUrl) => {
      const graphql = JSON.stringify({
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

      const myHeaders = new Headers();
      myHeaders.append("Content-Type", "application/json");

      const requestOptions = {
        method: "POST",
        headers: myHeaders,
        // mode: "cors", // no-cors, *cors, same-origin
        // cache: "no-cache", // *default, no-cache, reload, force-cache, only-if-cached
        // credentials: "same-origin", // include, *same-origin, omit
        body: graphql,
        redirect: "follow",
      };

      return fetch(`${baseUrl}/naive_api`, requestOptions)
        .catch((error) => console.error(error))
        .then((response) => response.json());
    };

    return await signUser(
      name,
      keypair,
      baseUrl
    );

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
