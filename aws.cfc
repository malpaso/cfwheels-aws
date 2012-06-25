<cfcomponent displayname="AWS Plugin" output="false">
	<cffunction name="init" output="false">
        <cfscript>
            this.version = "1.1.7,1.1.8";

            //Clear out the application scope cache
            lock timeout="20" scope="application" {
            	application.aws = {};
            	application.aws.jars = 'lib/httpcore-4.2.jar,lib/httpclient-4.2.jar,lib/jets3t-0.9.0.jar';
            }

            return this;
        </cfscript>
    </cffunction>

    <cffunction name="s3ListObjects" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfscript>
    		return $getRestS3Service().listObjects(arguments.bucket);
    	</cfscript>
    </cffunction>

    <cffunction name="s3ListObjectsChunked" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfargument name="prefix" type="string" default="#$null()#"/>
    	<cfargument name="delimiter" type="string" default="#$null()#"/>
    	<cfargument name="maxListingLength" type="numeric" default="1000"/>
    	<cfargument name="priorLastKey" type="string" default="#$null()#"/>
    	<cfargument name="completeListing" type="boolean" default="false"/>
    	<cfargument name="return" type="string" default="objects"/>
    	<cfscript>
    		var loc = {};
    		loc.chunk = $getRestS3Service().listObjectsChunked(
    										arguments.bucket,
    										arguments.prefix,
    										arguments.delimiter,
    										arguments.maxListingLength,
    										arguments.priorLastKey,
    										arguments.completeListing
    									);
    		if(arguments.return == 'prefixes')
    			return loc.chunk.getCommonPrefixes();

    		return loc.chunk.getObjects();
    	</cfscript>
    </cffunction>

    <cffunction name="s3GetObjectHeads" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfargument name="objects" type="any" required="true"/>
    	<cfscript>
    		return $getThreadedService().getObjectsHeads(arguments.bucket,arguments.objects);
    	</cfscript>
    </cffunction>

    <cffunction name="$getThreadedService" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'simpleThreadedStorageService')){
    			lock timeout="20" name="awsthreadedservicelock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.multi.SimpleThreadedStorageService');
	    			loc.obj.init($getRestS3Service(arguments.reload));
	    			
	    			application.aws.simpleThreadedStorageService = loc.obj;
    			}
    		}

    		return application.aws.simpleThreadedStorageService;
    	</cfscript>
    </cffunction>

    <cffunction name="$getRestS3Service" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'restS3Service')){
    			lock timeout="20" name="awsrests3lock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.impl.rest.httpclient.RestS3Service');
	    			loc.obj.init($getAWSCredentials(arguments.reload),$null(),$null(),$getAWSProperties(arguments.reload));
	    			
	    			application.aws.restS3Service = loc.obj;
    			}
    		}

    		return application.aws.restS3Service;
    	</cfscript>
    </cffunction>

     <cffunction name="$getAWSProperties" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'awsProperties')){
    			lock timeout="20" name="awspropertieslock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.Jets3tProperties');
	    			loc.obj.init();
	    			//Set the properties
	    			if(structKeyExists(application.wheels,'aws.jets3tproperties')){
	    				loc.props = get('aws.jets3tproperties');
	    				for(loc.key in loc.props){
	    					loc.obj.setProperty(lcase(loc.key),'#loc.props[loc.key]#');
	    				}
	    			}
	    			
	    			application.aws.awsProperties = loc.obj;
    			}
    		}

    		return application.aws.awsProperties;
    	</cfscript>
    </cffunction>

    <cffunction name="$getAWSCredentials" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'awsCredentials')){
    			lock timeout="20" name="awscredentialslock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.security.AWSCredentials');
	    			loc.obj.init(get('aws.accessKeyId'),get('aws.secretAccessKey'));
	    			
	    			application.aws.awsCredentials = loc.obj;
    			}
    		}

    		return application.aws.awsCredentials;
    	</cfscript>
    </cffunction>

    <cffunction name="$createJavaObject" returntype="any" output="false">
    	<cfargument name="class" type="string" required="true"/>
    	<cfargument name="classpath" type="string" default="#application.aws.jars#"/>
    	<cfscript>
    		//First see if the class is already on the classpath
    		if($classExists(arguments.class)){
    			return createObject('java',arguments.class);
    		}

    		//Now check if it is railo
    		if(structKeyExists(server,'railo') && len(arguments.classpath)){
    			//We can pass the classpath directly here
    			return createObject('java',arguments.class,arguments.classpath);
    		}

    		//TODO: Check if Adobe Coldfusion here in the future. Either use JavaLoader.cfc or see if CF10's new features will work

    		$throw(type="Wheels.Unable to create java object", message="Unable to create the java object with class name: #arguments.class#. You may running on an unsupported engine.");
    	</cfscript>
    </cffunction>

    <cffunction name="$classExists" returntype="boolean" output="false">
    	<cfargument name="class" type="string" required="true"/>
    	<cfscript>
    		var loc = {};
    		loc.returnValue = true;
			try {
				loc.class = createObject('java','java.lang.Class').forName(arguments.class,false,$null());
			}
			catch(any e){
				loc.returnValue = false;
			}

			return loc.returnValue;
    	</cfscript>
    </cffunction>

    <cffunction name="$null" returntype="any" output="false">
    	<cfreturn javaCast("null","")/>
    </cffunction>
</cfcomponent>