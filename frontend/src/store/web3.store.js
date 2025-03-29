import { defineStore } from 'pinia';
import { BuckItUpClient } from 'buckitup-sdk';
import { LIT_ABILITY, LIT_NETWORK } from '@lit-protocol/constants';
import { LitAccessControlConditionResource, createSiweMessage, generateAuthSig } from '@lit-protocol/auth-helpers';
import { LitNodeClient } from '@lit-protocol/lit-node-client';
import bcConfig from '../../../bcConfig.json';
import { ethers, Wallet } from 'ethers';

const mainChainId = IS_PRODUCTION ? '11155111' : '225'; //
const bc = bcConfig[mainChainId];

const provider = new ethers.providers.JsonRpcProvider(bc.chain.rpcUrl); // replace with your chain's RPC if needed
const registryContract = new ethers.Contract(bc.registry.address, JSON.parse(bc.registry.abijson), provider);
const vaultContract = new ethers.Contract(bc.vault.address, JSON.parse(bc.vault.abijson), provider);
export const web3Store = defineStore('web3', () => {
	const blockExplorer = 'https://localtrace.io';

	const bukitupClient = new BuckItUpClient();
	const litClient = new LitNodeClient({
		litNetwork: LIT_NETWORK.DatilTest,
	});

	const signTypedData = async (privateKey, domain, types, message) => {
		const signer = new Wallet(privateKey);
		const signature = await signer._signTypedData(domain, types, message);
		return signature;
	};

	const getSessionSigs = async (signer, capacityDelegationAuthSig) => {
		try {
			const resourceAbilityRequests = [
				{
					resource: new LitAccessControlConditionResource('*'),
					ability: LIT_ABILITY.AccessControlConditionDecryption,
				},
			];

			if (!litClient.ready) await litClient.connect();

			const sessionSignatures = await litClient.getSessionSigs({
				chain: 'sepolia',
				expiration: new Date(Date.now() + 1000 * 15).toISOString(), // 10 minutes
				capabilityAuthSigs: [capacityDelegationAuthSig], // Unnecessary on datil-dev
				resourceAbilityRequests,
				authNeededCallback: async ({ uri, expiration, resourceAbilityRequests }) => {
					const d = {
						uri,
						expiration,
						resources: resourceAbilityRequests,
						walletAddress: signer.address,
						nonce: await litClient.getLatestBlockhash(),
						litNodeClient: litClient,
					};
					if (!location.origin.includes('local')) {
						d.domain = location.host;
					}
					const toSign = await createSiweMessage(d);
					return await generateAuthSig({
						address: signer.address,
						signer,
						toSign,
					});
				},
			});
			//console.log('sessionSignatures', sessionSignatures);
			return sessionSignatures;
		} catch (error) {
			console.log('sessionSignatures', error);
		}
	};

	const addressShort = (address) => {
		if (address) return address.replace(address.substring(6, 38), '...');
		return '...';
	};

	const getAccessControlConditions = (tag, idx) => {
		const checkActionIpfs = 'QmezCK5USTbk2Wfwgk4va8FFZCjeimw1NgX3QCPLTBggsY';
		const checkActionIpfs5 = `
			const read = async (tag, idx, chainId) => {
				try {
					await fetch("https://buckitupss.appdev.pp.ua/api/backup/read?tag=" + tag + "&idx=" + idx + "&chainId=" + chainId);
					console.log('Action success');
				} catch (e) {
					console.log('Action error', e);
				}
				return true
			};
		`;

		const conditions = [
			{
				conditionType: 'evmContract',
				contractAddress: bc.vault.address,
				functionName: 'granted',
				functionParams: [tag.toString(), idx.toString(), ':userAddress'],
				functionAbi: {
					type: 'function',
					name: 'granted',
					constant: true,
					stateMutability: 'view',
					inputs: [
						{
							type: 'string',
							name: 'tag',
						},
						{
							type: 'uint8',
							name: 'idx',
						},
						{
							type: 'address',
							name: 'stealthAddress',
						},
					],
					outputs: [
						{
							type: 'bool',
							name: 'result',
						},
					],
				},
				chain: 'sepolia',
				returnValueTest: {
					key: 'result',
					comparator: '=',
					value: 'true',
				},
			},
			//{ operator: "and" },
			//{
			//  contractAddress: "ipfs://" + checkActionIpfs,
			//  standardContractType: "LitAction",
			//  chain: "sepolia",
			//  method: "read",
			//  parameters: [
			//      tag.toString(),
			//      idx.toString(),
			//      mainChainId
			//  ],
			//  returnValueTest: {
			//      comparator: "=",
			//      value: "true",
			//  },
			//}
		];
		console.log('conditions', conditions);
		return conditions;
	};

	return {
		//projectId,
		//mainChain,
		mainChainId,
		addressShort,
		bukitupClient,

		getSessionSigs,
		getAccessControlConditions,

		litClient,

		bc,
		//networks,
		//wagmiAdapter,

		blockExplorer,

		signTypedData,
		registryContract,
		vaultContract,
	};
});
