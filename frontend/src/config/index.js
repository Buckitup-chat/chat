import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { sepolia } from '@reown/appkit/networks'
import { http, createConfig } from '@wagmi/vue'
import bcConfig from '../../../bcConfig.json'

export const projectId = "b56e18d47c72ab683b10814fe9495694" // this is a public projectId only to use on localhost

const local = {
  id: 225,
  name: 'SecretL',
  network: 'local225',
  testnet: true,
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['http://127.0.0.1:31225'] },
    public: { http: ['http://127.0.0.1:31225'] },
  },
  blockExplorers: {
    default: { name: 'LocalTrace', url: 'https://localtrace.io' },
  },
};

export const mainChain = IS_PRODUCTION ? sepolia : local //
export const mainChainId = mainChain.id
export const bc = bcConfig[mainChainId]

export const networks = [sepolia, local]

export const metadata = {
  name: "Buckitup",
  description: "Buckitup Example",
  url: "https://buckitup.com",
  icons: ["https://avatars.githubusercontent.com/u/37784886"],
};

export const wagmiAdapter = new WagmiAdapter({
  networks,
  projectId
})

export const clientConfig = createConfig({
  chains: [sepolia, local],
  transports: {
    [sepolia.id]: http(),    
    [local.id]: http(),   
  },
})