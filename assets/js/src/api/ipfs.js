import { create } from 'ipfs-http-client';

//const ipfs = create({
//    host: '185.24.201.1',
//    port: 5001,
//    protocol: 'https',    
//});

const ipfs = create({
    host: 'ipfs.infura.io',    
    port: 5001,
    protocol: 'https',
    headers: {
        authorization: `Basic ${window.btoa(`${INFURA_PR_ID}:${INFURA_SERCET}`)}`,
    }
});

export const uploadToIPFS = async (file, options) => {    
    const result = await ipfs.add(file, options); 
    return result.cid.toV1().toString()      
};

export const uploadToIPFScid = async (file, options) => {    
    const result = await ipfs.add(file, options); 
    return result.cid      
};
