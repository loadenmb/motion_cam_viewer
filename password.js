#!/usr/bin/env node

'use strict';

var passwordLength = 8; // password length, max. < 256
var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#?!@$%^&*-'; // password charset, keep in mind to change regex below

var fs = require('fs');
var crypto = require('crypto');
var config = JSON.parse(fs.readFileSync('config.json', 'utf8'));

// escape chars in string for regex
var escapeRegExp = function(str) {
    return str.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&");
}

// no argument: create random password
if (typeof process.argv[2] == 'undefined' ||  process.argv[2].length == 0) {
    var rnd = crypto.randomBytes(passwordLength), 
    password = "", 
    len = Math.min(256, chars.length),
    d = 256 / len
    for (var i = 0; i < passwordLength; i++)
          password += chars[Math.floor(rnd[i] / d)];
    var hash = crypto.createHmac('sha512', config.secret).update(password).digest('hex');
    console.log(hash + " " + password);
} else {
    if (process.argv[2].match('^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[#?!@$%^&*-]).{8,}$')) { // change if password charset changes
         var hash = crypto.createHmac('sha512', config.secret).update(process.argv[2]).digest('hex');
         console.log(hash + " " + process.argv[2]);
    } else {
        console.log(1);
        process.exit(1);
    }
}
