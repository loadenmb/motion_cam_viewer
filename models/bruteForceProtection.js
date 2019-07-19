module.exports = {
    ips: [],
    maxTrials: 3,
    period: 3,
    banTime: 10,
    new: function(maxTrials, period, bantime) {
        this.maxTrials = maxTrials;
        this.period = period * 60; // sec to min
        this.bantime = bantime * 60;
        return this;
    },
    trialByIP: function(ip) {
        if (typeof this.ips[ip] == 'undefined')
            this.ips[ip] = [];
        this.ips[ip].push(this.getCurrentTime());
        return this;
    },
    resetTrialsByIP: function(ip) {
        this.ips[ip] = [];  
        return this;
    },
    isIPBanned: function(ip) {
        if (typeof this.ips[ip] != 'undefined') {
            if (this.ips[ip].length > this.maxTrials) {
                return true;
            } else if (this.ips[ip].length == this.maxTrials) {
                this.newInJail(ip);
                return true;
            }        
        }
        return false;
    },
    clearExpiredTrials: function() {
        for (var ip in this.ips) {
            for (var i = 0; i < this.ips[ip].length; i++) {
                if (this.ips[ip][i] - this.getCurrentTime() > this.period) {
                    this.ips[ip][i].splice(i, 1);
                }
            }        
        }         
    },
    newInJail: function(ip) {},
    jail: function(req, res, next) { // for hook in express stack
        module.exports.clearExpiredTrials();
        if (module.exports.isIPBanned(req.ip)) {
            next(new Error('Banned by brute force protection'));
        } else {
            next();
        }
    },
    getCurrentTime: function() {
        return Math.round(new Date().getTime() / 1000); // ms to seconds
    }
}; 
