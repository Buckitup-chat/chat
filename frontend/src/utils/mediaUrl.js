export const mediaUrl = (url, def) => {    
    if (!url) return def

    const ipfsCidPattern = /^(Qm[a-zA-Z0-9]{44}|bafy[a-zA-Z0-9]{48,})$/;

    if (ipfsCidPattern.test(url)) {
        return `${IPFS_URL}${url}`; // Format CID into a full URL
    }

    return url; // Return original if not an IPFS CID
};




