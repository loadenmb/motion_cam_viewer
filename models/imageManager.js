module.exports = {
    imagePath: "",
    JSZip: require('jszip'),
    fs: require('fs'),
    asyncLoop: require('../helper.js').asyncLoop,
    new: function(imagePath) {
        this.imagePath = imagePath;
        return this;
    },
    read: function(callback) {
        this.fs.readdir(this.imagePath, {withFileTypes: true}, function(error, files) {
            if (error) {
                callback(error);  
                return;
            }
            var images = [];         
            files.forEach(function(file) {
                if (file.isFile() && file.name.substr(-4) == '.jpg') {
                    images.push(file.name);
                }
            });
            images.sort(function (a, b) {
                a = a.toLowerCase();
                b = b.toLowerCase();
                if (a < b) return 1;
                if (a > b) return -1;
                return 0;
            });
            callback(images);
        });
    },
    deleteOne:  function(path, callback) {
        var imagePath = this.imagePath + path;
        var fs = this.fs;
        this.fs.lstat(imagePath, function(error, stats) {
            if (error) {
                callback(error);
                return;
            }
            if (stats.isFile() && imagePath.substr(-4) == '.jpg') {
                fs.unlink(imagePath, function(error) {
                    if (error) {
                        callback(error);
                        return;
                    }
                    callback(false);
                });  
            } else {
                callback(new Error('error: "' + imagePath + '" is not a image or not accessable.'));   
            }
        });    
    },
    delete: function(imagesArray, callback) {
        var self = this;
        this.asyncLoop(imagesArray.length, 
        function(loop) {
            self.deleteOne(imagesArray[loop.iteration()], function(error) {                
                if (error) {
                    callback(error);
                    return;
                }
            loop.next();
        })}, 
        function() {
            callback(false);
        });    
    },
    zip: function(imagesArray, callback) {
        var zip = new this.JSZip();
        var self = this;
        this.asyncLoop(imagesArray.length, 
        function(loop) {
            var image = imagesArray[loop.iteration()];
            self.fs.readFile(self.imagePath + image, function(err, data) {
                if (err) {
                  callback(err, null);
                  return;
                }
                zip.file(image, data);
                loop.next();  
            });
        }, 
        function() {                
            zip.generateAsync({
                type: 'nodebuffer',
                compression: 'DEFLATE',
                compressionOptions: {
                    level: 9
                }
            }).then(function(file) {
                callback(false, file);
            });            
        });         
    }
}; 
