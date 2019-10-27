#!/usr/bin/env node

'use strict';

// helper functions
var helper = require('./helper.js');
var pagination = helper.pagination;
var httpClientRequest = helper.httpClientRequest;
var sanitizePath = helper.sanitizePath;

// get config
var fs = require('fs');
var config = JSON.parse(fs.readFileSync(__dirname + '/config.json', 'utf8'));
config.motion_imagePath = sanitizePath(config.motion_imagePath);
config.motion_videoStreamUri = sanitizePath(config.motion_videoStreamUri);
config.motion_controlUri = sanitizePath(config.motion_controlUri);
config.publicWWW_relative = sanitizePath(config.publicWWW_relative);

// logger
if (config.log_enabled == true) {
    var logStream = fs.createWriteStream(config.logFile, {flags: 'a'});
    process.on('exit', function () {
        log('close log file');	
        logStream.end();
    });
    var log = function(msg) {
        msg = new Date().toLocaleString() + ': ' + msg;
        if (config.log2File_enabled == true) {
            logStream.write(msg + "\n"); 
        } else {
            console.log(msg);
        }
    }
} else {
    var log = function(msg) {} 
}

// set http client request options
var httpOptionsControl = {timeout: 80};
if (config.motion_controlUriAuth.length > 0)
    httpOptionsControl.auth = config.motion_controlUriAuth;

var express = require('express');
var https = require('https');
var app = express();
app.disable('x-powered-by');

// get local network ip address on first network interface (order: eth0, wlan0), set 127.0.0.1 if no local network available
var getLocalIP = function() {
    var os = require('os');
    var networkInterfaces = os.networkInterfaces();
    var addresses, address;
    for (var networkInterface in networkInterfaces) {
        addresses = networkInterfaces[networkInterface];
        for (var i = 0; i < addresses.length; i++) {
            address = addresses[i];
            if (address.internal == false) {
                if (address.netmask.substr(0, 4) != 'ffff') {
                    return address.address;
                }
            }
        }
    }
    return '127.0.0.1';
}
        
// webserver, return a array which include all HTTP server we spawn
var serve = function() {
    var server = [];
    
    // set network interface to lan if empty
    if (config.networkInterface.length == 0)
        config.networkInterface = getLocalIP();   
    
    // HTTP
    if (config.port != 0) {
        server.push(app.listen(config.port, config.networkInterface, function() {
            log('listening on: http://' + config.networkInterface + ':' + config.port);
        }));   
        
        // use localhost network interface for tor if not listening to 127.0.0.1 already
        if (config.tor_HiddenService_enabled == true && config.networkInterface != '127.0.0.1') {
            server.push(app.listen(config.port, '127.0.0.1', function() {
                log('listening on: http://' + '127.0.0.1' + ':' + config.port);
            }));      
        }
    }
    
    // HTTPS / SSL
    if (config.ssl_privateKeyPath.length != 0 && config.ssl_certificatePath.length != 0) {  
        server.push(https.createServer({
            key: fs.readFileSync(config.ssl_privateKeyPath).toString(),
            cert: fs.readFileSync(config.ssl_certificatePath).toString()
        }, app).listen(config.ssl_port, config.networkInterface, function() {
            log('listening on: https://' + config.networkInterface + ':' + config.ssl_port);
        }));
    }
    return server;
}

// ddos protection
if (config.ddos_enabled == true) {
    var Ddos = require('ddos');
    var ddos = new Ddos({
        burst: config.pagination_maxImagesPage + 5,
        limit: (config.pagination_maxImagesPage + 5) * 4 ,
        maxexpiry: config.ddos_maxexpiry,
        includeUserAgent: false, // ban by IP only, not IP + user agent
        responseStatus: 503, // make ddosers happy, show them success ;)
        onDenial: function(req) {
            log('banned IP: [' + req.ip + '] reason: ddos');
        }
    });
    app.use(ddos.express);
}

// parser for GET / POST request parameter
var bodyParser = require('body-parser');
app.use(bodyParser.urlencoded({
    extended: true,
    limit: config.pagination_maxImagesPage * 24 + 5,
    parameterLimit: config.pagination_maxImagesPage + 5 
}));

// brute force protection
var bruteForceProtection = require('./models/bruteForceProtection.js')
bruteForceProtection.newInJail = function(ip) {
    log('banned IP: [' + ip + '] reason: brute force');
}
bruteForceProtection.new(config.bruteForce_maxTrials, config.bruteForce_period, config.bruteForce_banTime);
app.use(bruteForceProtection.jail);

// serve static files / images
var serveStatic = require('serve-static');
app.use(serveStatic(__dirname + '/' + config.publicWWW_relative, {
    index: false, 
    etag: false, 
    maxAge: 10 * 60 * 1000  // min to ms  
}));
app.use(serveStatic(config.motion_imagePath, {
    index: false, 
    etag: false, 
    maxAge: 0 * 60 * 1000 
}));

// set express template engine
app.set('views', __dirname + '/views');
var ejs = require('ejs');
app.set('view engine', 'ejs');

// session for login / login check
var session = require('express-session');
app.use(session({
  secret: config.secret,
  resave: true,
  saveUninitialized: false
}));

// basic image management functionalities
var imageManager = require('./models/imageManager.js')
imageManager.new(config.motion_imagePath);

// express error handler
app.use(function(err, req, res, next) {
    // log(err);
    res.render('error');
});

/*
 * controller / routes
 */

// checks if logged in
var requiresLogin = function(req, res, next) {
    if (req.session && req.session.login) {
        return next();
    } else {
        res.render('error');
        return;        
    }
}

// proxy for webcam stream
var httpProxy = require('http-proxy');
var proxyOptions = {};
if (config.motion_videoStreamAuth.length > 0)
    proxyOptions.auth = config.motion_videoStreamAuth;
var proxy = httpProxy.createProxyServer(proxyOptions);
app.get('/stream/', requiresLogin, function(req, res) {
    proxy.web(req, res, { 
        target: config.motion_videoStreamUri,
        changeOrigin: true,
        ignorePath: true
    });
    proxy.on('error', function(err, req, res) {
        res.set('Content-Type', 'image/jpg');
        res.sendFile(__dirname + '/' + config.publicWWW_relative + 'placeholder.jpg');
    });
});

// list images / overview page
var overview = function(req, res) {    
    if (typeof req.session.login == 'undefined') {
        res.render('login');
    } else {    
        var templateData = {
            streamUri: "",
            motion_state: null,
            images: [],
            messages: [],
            pagination: {},
            snapshot_no_stream: false
        };
        var page = 1;
        if (typeof req.params['page'] != 'undefined' && req.params['page'] != 0) {
            if (null == req.params['page'].match(/^[0-9]+$/)) {
                res.render('error');
                return;
            }
            page = parseInt(req.params['page']);
        }
        
        // set stream uri for page 1 (display stream)
        if (page == 1)
            templateData.streamUri = config.motion_videoStreamUri; 
        
        // set snapshot on overview open instead of video stream on hidden service if domain ends with .onion and option is set
        var domainEnding = req.hostname.split('.');
        var offset = domainEnding.length - 1;
        if (offset > 0) {
            domainEnding = domainEnding[domainEnding.length - 1];
            if (config.tor_HiddenService_snapshot == true && domainEnding == "onion")
                templateData.snapshot_no_stream = true;
        }
        
        // get motion detection state
        httpClientRequest(config.motion_controlUri + '0/detection/status', httpOptionsControl, function(error, data) {
            if (error) {
                templateData.motion_state = null;
            } else {
                if (-1 != data.indexOf('PAUSE')) {                
                    templateData.motion_state = false;       
                } else if (-1 != data.indexOf('ACTIVE')) {
                    templateData.motion_state = true;
                } else {
                    templateData.motion_state = null;
                    log('unknown answer of motion http control service');
                }
            }
            
            // get images
            imageManager.read(function(images) {
                if (images instanceof Error) {
                    log(images);
                    res.render('error');
                    return;
                }
                var from = config.pagination_maxImagesPage * (page - 1);
                var to = from + config.pagination_maxImagesPage; 
                if (to > images.length)
                    to = images.length;
                templateData.images = images.slice(from, to); 
                templateData.pagination = pagination(page, images.length, config.pagination_maxImagesPage, 5);   
                res.render('overview', templateData);           
            });
        }); 
    }
};
app.get('/', overview);
app.get('/page/:page', overview);

// get state + enable / disable cam
app.get('/toggle/', requiresLogin, function(req, res) {    
    httpClientRequest(config.motion_controlUri + '0/detection/status', httpOptionsControl, function(error, data) {
        if (error) {
            log(error.message);
        }
        if (-1 != data.indexOf('PAUSE')) {                
            httpClientRequest(config.motion_controlUri + '0/detection/start', httpOptionsControl, function(error, data) {
                if (error) {
                    log(error.message);
                }  
            });
        } else if (-1 != data.indexOf('ACTIVE')) {
            httpClientRequest(config.motion_controlUri + '0/detection/pause', httpOptionsControl, function(error, data) {
                if (error) {
                    log(error.message);
                }
            }); 
        } else {
            log('unknown answer of motion http control service while toggle');
        }
        res.redirect('/');
    });    
});

// do snapshot
app.get('/snapshot/', requiresLogin, function(req, res) {
    httpClientRequest(config.motion_controlUri + '0/action/snapshot', httpOptionsControl, function(error, data) {
        if (error) {
            log(error.message);
        }  
        if (-1 != data.indexOf('Done')) {
            
        } else {
            log('unknown answer of motion http control service while snapshot');   
        }
        res.redirect('/');
    });
}); 

// force zip download
var forceDownload = function(images, res) {
    imageManager.zip(images, function(error, file) {
        if (error) {
            log(error);
            res.render('error');
            return;                    
        }
        res.set('Content-Type', 'application/zip');
        res.set('Content-Disposition', 'attachment;filename="motioncam-' + new Date().toLocaleString() + '.zip"');
        res.send(file);
    });    
}

// execute selected action
app.post('/execute/', requiresLogin, function(req, res) { 
    if (typeof req.body['images'] == 'undefined' || typeof req.body['action'] == 'undefined' || typeof req.body['action'] != 'string') { 
        res.redirect('/');  
        return;
    }      
    if (typeof req.body['images'] == 'string') {
        var images = [];
        images[0] = req.body['images'];
    } else if (typeof req.body['images'] == 'object') {
        var images = req.body['images']; 
    } else {
        res.redirect('/');  
        return;      
    }     
    
    // "basename" for all images
    images.map(function(path) {
        return path.split('/').reverse()[0];
    });
    
    switch(req.body['action']) {
        
        // delete selected images
        case 'delete':                
            imageManager.delete(images, function(error) {
                if (error) {
                    log(error);
                    res.render('error');
                } else {
                    res.redirect('/');   
                }
            });

            break;
        
        // download selected images as zip
        case 'download':      
            forceDownload(images, res);
            break;
    }
});

// download all images
app.get('/download/', requiresLogin, function(req, res) { 
    imageManager.read(function(images) {
        if (images instanceof Error) {
           log(error);
            res.render('error');
            return;
        }
        forceDownload(images, res);
    });
});


// delete all images
app.get('/clear/', requiresLogin, function(req, res) { 
    imageManager.read(function(images) {
        if (images instanceof Error) {
           log(error);
            res.render('error');
            return;
        }
        imageManager.delete(images, function(error) {
            if (error) {
                log(error);
                res.render('error');
                return;
            } 
            res.redirect('/'); 
        });                         return;
    });
});

// login action
var crypto = require('crypto');
app.post('/login/', function(req, res) {
    if (typeof req.session.login == 'undefined' && typeof req.body['password'] == 'string') {
        if (crypto.createHmac('sha512', config.secret).update(req.body['password']).digest('hex') == config.password) {
            req.session.login = true;
            bruteForceProtection.resetTrialsByIP(req.ip);  
        } else {
            bruteForceProtection.trialByIP(req.ip);  
        }
    } else {
        bruteForceProtection.trialByIP(req.ip); // maybe ignore empty login trials   
    }
    res.redirect('/'); 
});

// logout action
app.get('/logout/', requiresLogin, function(req, res) {
    if (req.session) {
        req.session.destroy(function(error) {
            if (error) {
                res.render('error');
            } else {
                res.redirect('/');
            }
        });
    }
});

// 404 errors
app.use(function(req, res) {
    res.render('error');
});

serve();


