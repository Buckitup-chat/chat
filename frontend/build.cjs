const { exec } = require('child_process'); // For running shell commands
const { NodeSSH } = require('node-ssh');
const {
	promises: { readFile, unlink },
} = require('fs');
const AdmZip = require('adm-zip');

const path = require('path');
const ssh = new NodeSSH();

const config = {
	host: '135.181.151.155',
	port: '7342',
	username: 'roma',
	privateKey: 'E:/Archive/hetzner/openssh', // Use SSH key authentication
};

// Path to deploy on VPS
const remotePath = '/home/roma/www/buckitupss/app'; //_dev

// Step 1: Build the Vite project
console.log('Building the Vite project...');
const buildProcess = exec('npm run build');

// Log build stdout in real-time
buildProcess.stdout.on('data', (data) => {
	console.log(data.toString());
});

// Log build stderr in real-time
buildProcess.stderr.on('data', (data) => {
	console.error(data.toString());
});

// Handle build completion
buildProcess.on('close', async (code) => {
	if (code !== 0) {
		console.error(`Build process exited with code ${code}`);
		return;
	}
	console.log('Build successful. Starting file upload...');

	try {
		config.privateKey = await readFile(config.privateKey, 'utf-8');
		await ssh.connect(config);
		console.log('Connected to the VPS. Uploading files...');
		const removeCommand = `rm -rf ${remotePath}/*`;
		const removeResult = await ssh.execCommand(removeCommand);
		if (removeResult.stderr) {
			throw new Error(`Error cleaning remote directory: ${removeResult.stderr}`);
		}
		console.log('Remote directory cleaned successfully.');

		// Step 3: Zip the dist directory
		const localDistPath = path.join(__dirname, 'dist');
		const zipPath = path.join(__dirname, 'dist.zip');

		console.log('Zipping dist directory...');
		const zip = new AdmZip();
		zip.addLocalFolder(localDistPath);
		zip.writeZip(zipPath);
		console.log('Dist folder zipped successfully!');

		// Step 5: Upload the zip file
		const remoteZipPath = `${remotePath}/dist.zip`;
		await ssh.putFile(zipPath, remoteZipPath);
		console.log('Zip file uploaded successfully!');

		// Step 6: Unzip the file on the server
		console.log('Unzipping file on the server...');
		await ssh.execCommand(`unzip -o ${remoteZipPath} -d ${remotePath}`);
		console.log('Files unzipped successfully on the server!');

		// Step 7: Clean up by removing the zip file from the server
		await ssh.execCommand(`rm -f ${remoteZipPath}`);
		console.log('Remote zip file deleted successfully!');

		// Step 8: Clean up the local zip file
		await unlink(zipPath);
		console.log('Local zip file deleted successfully!');

		// Step 9: Close the SSH connection
		ssh.dispose();
		console.log('SSH connection closed.');
	} catch (error) {
		console.error(`Error: ${error.message}`);
	}
});
