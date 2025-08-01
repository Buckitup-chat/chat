import SocketIO from 'socket.io-client';

export default SocketIO(API_SURL, {
	path: API_SPATH + '/socket.io/',
	autoConnect: false,
	extraHeaders: { 'Access-Control-Allow-Credentials': true },
});
