const http = require('http');
const os = require('os');

const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>K3s Test App</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          max-width: 800px;
          margin: 50px auto;
          padding: 20px;
          background: #f5f5f5;
        }
        .container {
          background: white;
          padding: 30px;
          border-radius: 10px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .info { 
          background: #e3f2fd; 
          padding: 15px; 
          border-radius: 5px;
          margin: 20px 0;
        }
        .success { color: #4caf50; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🚀 K3s Deployment Successful!</h1>
        <p class="success">Your k3s cluster is working perfectly!</p>
        
        <div class="info">
          <h3>Server Information:</h3>
          <p><strong>Hostname:</strong> ${os.hostname()}</p>
          <p><strong>Node Version:</strong> ${process.version}</p>
          <p><strong>Platform:</strong> ${os.platform()}</p>
          <p><strong>Environment:</strong> ${process.env.NODE_ENV || 'development'}</p>
          <p><strong>Request URL:</strong> ${req.url}</p>
        </div>
        
        <div class="info">
          <h3>Next Steps:</h3>
          <ul>
            <li>✅ K3s cluster is running</li>
            <li>✅ Ingress controller configured</li>
            <li>✅ HTTPS certificates working</li>
            <li>📦 Deploy your apps from Gitea CI</li>
          </ul>
        </div>
        
        <p style="text-align: center; color: #666; margin-top: 30px;">
          Powered by k3s on Hetzner | ci.gmac.io
        </p>
      </div>
    </body>
    </html>
  `);
});

server.listen(port, () => {
  console.log(\`Server running on port \${port}\`);
});