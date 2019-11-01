module.exports = {
    
    // works like async.eachSeries (loop some ansync functions, keep variables / execution order, execute callback when ready)
    asyncLoop: function(iterations, func, callback) {
        var index = 0;
        var done = false;
        var loop = {
            next: function() {
                if (done) {
                    return;
                }
                if (index < iterations) {
                    index++;
                    func(loop);
                } else {
                    done = true;
                    callback();
                }
            },
            iteration: function() {
                return index - 1;
            },
            break: function() {
                done = true;
                callback();
            }
        };
        loop.next();
        return loop;
    },
    pagination: function(page, maxResults, limit, display) {
        if (maxResults / limit < 1) {
            var lastPageToDisplay = 1;	
        } else {
            var lastPageToDisplay = Math.ceil(maxResults / limit);
        }
        var from = page - Math.floor(display / 2);
        var to = page + Math.floor(display / 2);       
        var tmp = 0;
        if (from <= 0) {
            tmp = to + from * -1;
            if (tmp <= lastPageToDisplay) {
                to = tmp;
            }
            from = 1;
        }
        if (to > lastPageToDisplay) {
            tmp = from + (to - lastPageToDisplay) * -1;   
            if (tmp > 0)
                from = tmp;
            to = lastPageToDisplay;
        }
        return {
            display: display,
            max: maxResults,	
            current: page,
            from: from,
            to: to,
            last: lastPageToDisplay	
        };
    },    
    httpClientRequest: function(uri, options, callback) {      
        var http = require('http');
        var req = http.get(uri, options, function(requestRes) {
            var bodyChunks = "";
            requestRes.on('data', function(chunk) {
                bodyChunks += chunk;
            }).on('end', function() {
                callback(false, bodyChunks);
            });
        }).on('error', function(e) {
            callback(e.message, "");
        });     
    },
    sanitizePath: function(path) {
        if (path[path.length - 1] != '/')
            return path + '/';
        return path;
    }
}
